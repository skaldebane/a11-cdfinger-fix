#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib.sh"
close_inherited_lock
umask 077
INCIDENT=$1
OLD_PID=$2
NEW_PID=$3
DEST="$STATE/incidents/$INCIDENT"
[ -d "$DEST" ] && [ ! -L "$DEST" ] || exit 1

process_snapshot() {
  pid=$1
  label=$2
  valid_hal_pid "$pid" || return 0
  {
    echo "PID $pid ($label)"
    cat "/proc/$pid/stat" "/proc/$pid/status" "/proc/$pid/oom_score_adj" 2>/dev/null
    ls -l "/proc/$pid/fd" 2>/dev/null
    count=0
    for task in /proc/"$pid"/task/*; do
      [ -d "$task" ] || continue
      echo "THREAD ${task##*/}"
      cat "$task/comm" "$task/wchan" "$task/stack" 2>/dev/null
      count=$((count + 1))
      [ "$count" -lt 16 ] || break
    done
  } | tail -c 131072 > "$DEST/process-$label.txt"
}

process_snapshot "$OLD_PID" previous
process_snapshot "$NEW_PID" initial
save_command "$DEST/fingerprint-initial.txt" 5 /system/bin/dumpsys fingerprint
save_command "$DEST/biometric-initial.txt" 5 /system/bin/dumpsys biometric
save_command "$DEST/interrupts.txt" 3 /system/bin/sh -c 'cat /proc/interrupts | grep -iE "finger|silfp"'
save_command "$DEST/qsee-app-state.txt" 3 /system/bin/cat /sys/kernel/debug/qseecom/app_info
save_command "$DEST/kernel-initial.txt" 3 /system/bin/sh -c 'dmesg | grep -iE "fingerprint|vendor[.]fps_hal|cdfinger|silead|silfp|qseecom|genirq.*finger" | grep -ivE "template|featureitem|featuretable|encapsulated|auth.?token|image.?data"'

sleep 10
hal_state
echo "Follow-up: $(date -u +%Y-%m-%dT%H:%M:%SZ) $SIGNATURE" >> "$DEST/summary.txt"
process_snapshot "$HAL_PID" followup
save_command "$DEST/hal-registration.txt" 6 /system/bin/sh -c 'lshal 2>/dev/null | grep -iE "fingerprint|qseecom"'
save_command "$DEST/fingerprint-followup.txt" 5 /system/bin/dumpsys fingerprint
copy_context "$DEST/after"

# Diagnostic ptrace only when registration is missing despite a live process.
# Never debuggerd a healthy HAL, never dump memory, never kill/restart anything.
if valid_hal_pid "$HAL_PID" && [ "$SERVICE" = running ] && \
  ! grep -q 'android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default' "$DEST/hal-registration.txt"; then
  save_command "$DEST/native-backtrace.txt" 12 /system/bin/debuggerd -b "$HAL_PID"
fi

size=$(du -sk "$DEST" | awk '{print $1}')
if [ "$size" -gt "$INCIDENT_BUDGET_KB" ]; then
  # Output caps normally keep a bundle well below this. Drop duplicated context first.
  rm -r "$DEST/after"
  echo 'Duplicate follow-up log context removed to enforce incident size limit.' >> "$DEST/summary.txt"
fi
echo "Capture complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DEST/summary.txt"
