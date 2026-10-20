#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/lib.sh"
check_compatibility || exit 1
prepare_state
# Android mksh marks shell-opened FDs close-on-exec. Let BusyBox open and
# retain the lock across exec rather than passing mksh's FD to external flock.
if [ "$1" != --locked ]; then
  exec /data/adb/magisk/busybox flock -n "$STATE/run.lock" /system/bin/sh "$0" --locked
fi
echo "$$" > "$STATE/daemon.pid"

LOG_PID=
KERNEL_PID=
SNAPSHOT_PID=
cleanup() {
  trap - EXIT TERM INT
  for pid in "$LOG_PID" "$KERNEL_PID" "$SNAPSHOT_PID"; do
    valid_pid "$pid" || continue
    kill -TERM "-$pid" 2>/dev/null
  done
  record 'Monitor stopped.'
  rm -f "$STATE/daemon.pid"
  exit 0
}
trap cleanup EXIT TERM INT

start_collectors() {
  if ! valid_pid "$LOG_PID"; then
    /system/bin/setsid /system/bin/sh "$MODDIR/collector.sh" logcat > /dev/null 2>&1 &
    LOG_PID=$!
    record "Started logcat collector PID $LOG_PID."
  fi
  if ! valid_pid "$KERNEL_PID"; then
    /system/bin/setsid /system/bin/sh "$MODDIR/collector.sh" kernel > /dev/null 2>&1 &
    KERNEL_PID=$!
    record "Started kernel collector PID $KERNEL_PID."
  fi
}

capture_incident() {
  reason=$1
  old_pid=$2
  new_pid=$3
  prune_incidents
  # Uptime suffix distinguishes captures if the wall clock moves backwards.
  read -r uptime_value unused < /proc/uptime
  INCIDENT="incident-$(date -u +%Y%m%dT%H%M%SZ)-${uptime_value%%.*}"
  mkdir -p "$STATE/incidents/$INCIDENT"
  {
    echo "Incident: $INCIDENT"
    echo "Reason: $reason"
    echo "UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Boot ID: $(cat /proc/sys/kernel/random/boot_id)"
    echo "Previous state: $PREVIOUS"
    echo "Current state: $SIGNATURE"
    echo "Vendor firmware: $(getprop ro.vendor.build.fingerprint)"
    echo 'No automatic recovery, authentication bypass, or kernel tracing.'
    [ "$reason" != self-test ] || echo 'SIMULATED TEST: no real fault was detected.'
    [ -z "$EVENT" ] || echo "Last matching log event: $EVENT"
  } > "$STATE/incidents/$INCIDENT/summary.txt"
  copy_context "$STATE/incidents/$INCIDENT/before"
  echo "$INCIDENT" > "$STATE/latest-incident"
  notify_incident "$INCIDENT" "$reason"
  /system/bin/setsid /system/bin/sh "$MODDIR/snapshot.sh" "$INCIDENT" "$old_pid" "$new_pid" > /dev/null 2>&1 &
  SNAPSHOT_PID=$!
  record "Capture $INCIDENT ($reason); snapshot PID $SNAPSHOT_PID."
}

hal_state
PREVIOUS=$SIGNATURE
PREVIOUS_PID=$HAL_PID
LAST_EVENT=$(latest_event)
LAST_CAPTURE=0
TICK=0
record "Monitor started PID $$; baseline $PREVIOUS."
while ! module_disabled; do
  start_collectors
  hal_state
  EVENT=$(latest_event)
  reason=$(event_reason "$PREVIOUS" "$SIGNATURE" "$LAST_EVENT" "$EVENT")
  LAST_EVENT=$EVENT
  if [ -f "$STATE/capture-request" ]; then
    read -r requested < "$STATE/capture-request"
    rm -f "$STATE/capture-request"
    case "$requested" in self-test) reason=self-test ;; *) reason=manual ;; esac
  fi
  now=$(date +%s)
  if [ -n "$reason" ]; then
    if valid_pid "$SNAPSHOT_PID"; then
      record "Coalesced event during capture: $reason $PREVIOUS -> $SIGNATURE"
    elif [ "$reason" = manual ] || [ "$reason" = self-test ] || [ $((now - LAST_CAPTURE)) -ge "$CAPTURE_COOLDOWN" ]; then
      capture_incident "$reason" "$PREVIOUS_PID" "$HAL_PID"
      LAST_CAPTURE=$now
    else
      record "Capture cooldown: $reason $PREVIOUS -> $SIGNATURE"
    fi
  fi
  PREVIOUS=$SIGNATURE
  PREVIOUS_PID=$HAL_PID
  echo "pid=$$ state=$SIGNATURE utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/status.txt"
  TICK=$((TICK + 1))
  if [ "$TICK" -ge 30 ] && ! valid_pid "$SNAPSHOT_PID"; then
    prune_incidents
    TICK=0
  fi
  sleep "$POLL_SECONDS"
done
