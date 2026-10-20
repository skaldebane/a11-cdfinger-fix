#!/system/bin/sh

# No downloaded executables, app data, fingerprint templates, or /proc/*/mem.
STATE=/data/adb/a11-fingerprint-monitor
POLL_SECONDS=2
CAPTURE_COOLDOWN=60
NOTIFY_COOLDOWN=600
MAX_INCIDENTS=6
BUDGET_KB=49152
INCIDENT_BUDGET_KB=6144
LOG_PATTERN='Failed to send cmd|QSEECom_send_cmd|[Ee]rror|[Ff]ailed|[Ff]ailure|[Ff]atal|exited|killed|Opening fingerprint|module is working|Fingerprint HAL not available|Daemon was null|vendor[.]fps_hal|IBiometricsFingerprint|silfp_nl_deinit|silfp_resource_init|STATE_EXIT'
EVENT_PATTERN='Failed to send cmd|Fingerprint HAL not available|HAL died|binderDied|Fatal signal.*fingerprint'

prepare_state() {
  umask 077
  mkdir -p "$STATE/incidents"
  chmod 700 "$STATE" "$STATE/incidents"
}

close_inherited_lock() {
  # Long-lived collectors must not keep the daemon's flock alive if it dies.
  for descriptor in /proc/$$/fd/*; do
    number=${descriptor##*/}
    case "$number" in ''|*[!0-9]*) continue ;; esac
    [ "$number" -gt 2 ] || continue
    [ "$(readlink "$descriptor" 2>/dev/null)" = "$STATE/run.lock" ] || continue
    eval "exec $number>&-"
  done
}

valid_pid() {
  case "$1" in ''|*[!0-9]*|0|1) return 1 ;; esac
  [ -d "/proc/$1" ]
}

valid_hal_pid() {
  valid_pid "$1" || return 1
  tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null |
    grep -q '^/vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service'
}

module_disabled() {
  for base in "$MODDIR" /data/adb/modules/a11_fingerprint_monitor; do
    [ -e "$base/disable" ] || [ -e "$base/remove" ] || continue
    return 0
  done
  return 1
}

record() {
  if [ -f "$STATE/monitor.log" ] && [ "$(wc -c < "$STATE/monitor.log")" -gt 65536 ]; then
    mv -f "$STATE/monitor.log" "$STATE/monitor.log.1"
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$STATE/monitor.log"
}

hal_state() {
  SERVICE=$(getprop init.svc.vendor.fps_hal)
  HAL_PID=$(getprop init.svc_debug_pid.vendor.fps_hal)
  valid_hal_pid "$HAL_PID" || HAL_PID=none
  SIGNATURE="$SERVICE:$HAL_PID"
}

event_reason() {
  if [ "$1" != "$2" ]; then
    echo hal-lifecycle-change
  elif [ -n "$4" ] && [ "$3" != "$4" ]; then
    echo hal-error-log
  fi
}

latest_event() {
  [ -f "$STATE/logcat.log" ] || return 0
  tail -n 160 "$STATE/logcat.log" | grep -E "$EVENT_PATTERN" | tail -n 1
}

# Snapshot output is bounded even when a diagnostic command hangs or floods.
save_command() {
  destination=$1
  seconds=$2
  shift 2
  /system/bin/timeout "$seconds" "$@" 2>&1 | tail -c 131072 > "$destination"
}

copy_context() {
  destination=$1
  mkdir -p "$destination"
  for file in "$STATE"/logcat.log* "$STATE"/kernel.log*; do
    [ -f "$file" ] || continue
    tail -c 65536 "$file" > "$destination/${file##*/}"
  done
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

notify_incident() {
  incident=$1
  reason=$2
  now=$(date +%s)
  last=0
  [ ! -f "$STATE/last-notification" ] || read -r last < "$STATE/last-notification"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ "$reason" != self-test ] && [ "$reason" != manual ] && [ $((now - last)) -lt "$NOTIFY_COOLDOWN" ]; then
    record "Notification coalesced for $incident ($reason)."
    return
  fi
  title='Fingerprint monitor: incident captured'
  [ "$reason" != self-test ] || title='Fingerprint monitor: self-test'
  [ "$reason" != manual ] || title='Fingerprint monitor: manual capture'
  message="Event: $reason. Incident: $incident (UTC). Initial evidence saved; follow-up capture is running. Message this incident ID to investigate over ADB. No automatic recovery performed."
  # Give system_server pipe FDs, not our root-private output-file FD: SELinux
  # can reject binder shellCommand when handed a file under /data/adb directly.
  {
    # Post as Android Shell, not UID 0's special root package. The user-facing
    # Shell channel is verified on this firmware; evidence files stay root-only.
    /system/bin/timeout 5 su 2000 -c "/system/bin/cmd notification post -t $(shell_quote "$title") -S bigtext fp-monitor $(shell_quote "$message")"
    echo "monitor_notification_status=$?"
  } 2>&1 | tail -c 8192 > "$STATE/notification-result.txt"
  sleep 1
  /system/bin/timeout 3 /system/bin/cmd notification get '0|com.android.shell|2020|fp-monitor|2000' \
    2>&1 | tail -c 8192 > "$STATE/notification-check.txt"
  if grep -q '^posting:' "$STATE/notification-result.txt" && \
    grep -q '^monitor_notification_status=0$' "$STATE/notification-result.txt" && \
    grep -Fq "$incident" "$STATE/notification-check.txt"; then
    echo "$now" > "$STATE/last-notification"
    record "Notification posted for $incident ($reason)."
  else
    record "Notification failed for $incident; see notification-result.txt."
  fi
}

prune_incidents() {
  # Only generated incident directories beneath our private directory qualify.
  # Names sort chronologically; never follow symlinks or touch unrelated paths.
  count=0
  for dir in "$STATE"/incidents/incident-*; do
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    count=$((count + 1))
  done
  for dir in "$STATE"/incidents/incident-*; do
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    usage=$(du -sk "$STATE" | awk '{print $1}')
    if [ "$count" -le "$MAX_INCIDENTS" ] && [ "$usage" -le "$BUDGET_KB" ]; then
      break
    fi
    record "Pruning ${dir##*/} (count=$count, usage=${usage}KiB)."
    rm -r "$dir"
    count=$((count - 1))
  done
}
