#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib.sh"
close_inherited_lock
umask 077
case "$1" in
  logcat)
    exec /system/bin/logcat -b main,system,crash -v threadtime -T 1 \
      -r 1024 -n 3 -f "$STATE/logcat.log" -e "$LOG_PATTERN" \
      'cdfinger:D' 'cdfingerHAL:I' 'QSEECOMAPI:W' 'fingerprint:W' \
      'android.hardware.biometrics.fingerprint@2.1-service:D' \
      'Fingerprint21:W' 'init:I' 'hwservicemanager:I' 'libc:F' '*:S'
    ;;
  kernel)
    # The controller gives this pipeline its own process group for cleanup.
    /system/bin/dmesg -w 2>/dev/null | /data/adb/magisk/busybox awk \
      -v path="$STATE/kernel.log" -v limit=524288 -f "$MODDIR/kernel-log.awk"
    ;;
  *) exit 1 ;;
esac
