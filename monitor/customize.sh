#!/system/bin/sh
[ "$BOOTMODE" = true ] || abort '! Install from Magisk in running Android.'
[ "$MAGISK_VER_CODE" -ge 20400 ] || abort '! Magisk 20.4 or newer is required.'
. "$MODPATH/common.sh"
check_compatibility || abort '! Unsupported device, firmware, or sensor.'
for tool in /system/bin/logcat /system/bin/dmesg /system/bin/timeout /system/bin/setsid /system/bin/flock /data/adb/magisk/busybox; do
  [ -x "$tool" ] || abort "! Required tool missing: $tool"
done
command -v su >/dev/null 2>&1 || abort '! Magisk su is required for Shell notification identity.'
set_perm_recursive "$MODPATH" 0 0 0755 0644
for file in service.sh daemon.sh collector.sh control.sh action.sh uninstall.sh; do
  set_perm "$MODPATH/$file" 0 0 0755
done
ui_print '- Passive monitor; no HAL restarts, kernel tracing, or security changes.'
ui_print '- Root-only logs: /data/adb/a11-fingerprint-monitor'
ui_print '- Bounded logs/incidents; notifications use the Android Shell channel.'
ui_print '- Disable in Magisk to stop; uninstall retains diagnostic evidence.'
