#!/system/bin/sh
MODDIR=${0%/*}
# Start after ordinary boot activity; do not flag expected early HAL startup.
attempt=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$attempt" -lt 90 ]; do
  sleep 2
  attempt=$((attempt + 1))
done
/system/bin/sh "$MODDIR/control.sh" start
