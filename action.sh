#!/system/bin/sh

# Optional Magisk action: restart only the fingerprint HAL, not Android.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
check_compatibility || exit 1

if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
  echo 'Module is disabled or pending removal; not restarting the HAL.'
  exit 1
fi

TARGET=/vendor/lib/hw/fingerprint.silead.default.so
if [ ! -f "$TARGET" ] || [ -s "$TARGET" ]; then
  echo 'Silead overlay is not active. Reboot to activate the installed module first.'
  exit 1
fi

if setprop ctl.restart vendor.fps_hal; then
  echo 'Fingerprint HAL restart requested. Wait a few seconds, then try your fingerprint.'
else
  echo 'Could not request a fingerprint HAL restart.'
  exit 1
fi
