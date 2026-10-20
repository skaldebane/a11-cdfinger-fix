#!/system/bin/sh
MODDIR=${0%/*}
/system/bin/sh "$MODDIR/control.sh" stop
# Deliberately retain evidence; never delete diagnostic records on uninstall.
