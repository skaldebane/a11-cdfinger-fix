#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib.sh"
prepare_state

monitor_pid() {
  MONITOR_PID=
  [ ! -f "$STATE/daemon.pid" ] || read -r MONITOR_PID < "$STATE/daemon.pid"
  valid_pid "$MONITOR_PID" || return 1
  # PID files can outlive a reboot; never signal an unrelated reused PID.
  tr '\000' ' ' < "/proc/$MONITOR_PID/cmdline" | grep -q '/a11_fingerprint_monitor/daemon.sh'
}

case "$1" in
  start)
    if monitor_pid; then
      echo "Already running: $MONITOR_PID"
      exit 0
    fi
    module_disabled && { echo 'Module disabled/pending removal.'; exit 1; }
    /system/bin/setsid /system/bin/sh "$MODDIR/daemon.sh" > /dev/null 2>&1 < /dev/null &
    sleep 1
    monitor_pid || { echo 'Monitor failed to start; run daemon.sh in foreground for diagnostics.'; exit 1; }
    echo "Monitor running: $MONITOR_PID"
    ;;
  stop)
    if monitor_pid; then
      kill -TERM "$MONITOR_PID"
      echo 'Monitor stop requested; evidence retained.'
    else
      echo 'Monitor is not running.'
    fi
    ;;
  capture|self-test)
    monitor_pid || { echo 'Monitor is not running; start it first.'; exit 1; }
    echo "$1" > "$STATE/capture-request"
    echo "Capture requested ($1)."
    ;;
  status)
    if monitor_pid; then echo "Running: $MONITOR_PID"; else echo 'Not running.'; fi
    cat "$STATE/status.txt" "$STATE/latest-incident" 2>/dev/null
    du -sk "$STATE"
    ;;
  *) echo 'Usage: control.sh start|stop|status|capture|self-test'; exit 1 ;;
esac
