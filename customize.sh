#!/system/bin/sh

# Sourced by Magisk's installer after normal ZIP extraction.
[ "$BOOTMODE" = true ] || abort '! Install from Magisk in a running Android system.'
[ "$MAGISK_VER_CODE" -ge 20400 ] || abort '! Magisk 20.4 or newer is required.'

. "$MODPATH/common.sh"
check_compatibility || abort '! This module is not validated for this device/firmware/sensor.'
[ -s /vendor/lib/hw/cdfinger.fingerprint.default.so ] || abort '! cdfinger HAL library is missing.'

PAYLOAD="$MODPATH/system/vendor/lib/hw/fingerprint.silead.default.so"
[ -f "$PAYLOAD" ] && [ ! -s "$PAYLOAD" ] || abort '! Expected an empty Silead overlay file.'

set_perm_recursive "$MODPATH/system/vendor" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print '- Supported Galaxy A11 / Android 12 / cdfinger configuration verified.'
ui_print '- Masks only the unused Silead HAL library using a systemless overlay.'
ui_print '- No authentication bypass, polling daemon, or SELinux-policy changes.'
ui_print '- Reboot once to activate normally; installation does not restart services.'
ui_print '- Disable/remove this module BEFORE upgrading firmware.'
