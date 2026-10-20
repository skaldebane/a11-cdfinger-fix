# Passive fingerprint monitor

An **independent, optional Magisk module**, not part of the cdfinger workaround.
Same narrow device/firmware/sensor installation checks as the main module.
It observes failures; it never restarts the HAL or changes authentication,
enrollment, SELinux policy, system properties, or kernel tracing configuration.

## Capture strategy

- Two-second checks of init's fingerprint HAL state/PID, plus matching error logs.
- Continuously rotating, filtered main/system/crash logs: four 1 MiB chunks.
- Continuously filtered kernel logs: four 512 KiB chunks.
- Lifecycle changes, selected errors, and manual requests create incidents with
  preceding log context, initial and follow-up service dumps, process/thread
  state, relevant IRQ and QSEE application state, and post-event context.
- If the HAL is still alive but its interface is absent at follow-up, attempt a
  time-limited nonfatal native backtrace. This briefly attaches to the process;
  healthy registered HALs are not attached to. A registration-query failure can
  also lead to a diagnostic attachment. No raw process-memory dump is taken.
- Snapshot work runs separately so lifecycle polling and log collection continue.
- Incidents at most once per minute, maximum six retained. Notifications at most
  once per ten minutes, replacing a single card. Manual/self-test requests bypass
  the notification cooldown. Events during capture/cooldown are recorded in
  `monitor.log`; continuous logs retain the surrounding sequence.
- Private storage budget: 48 MiB, checked each minute and around incidents.
  Each diagnostic output is capped at 128 KiB, context files at 64 KiB. The budget
  is a retention target, not a filesystem quota: brief overshoot is possible.

Notifications use Android Shell's notification channel. They contain the reason,
UTC incident ID, and a reminder to contact the investigator, not raw log contents.
They do not upload or automatically contact anyone. They don't open private
incident files when tapped. Sound, heads-up display, lock-screen behavior, and
Do Not Disturb are governed by the user's notification settings. Delivery is
attempted and its command result saved, but alerts cannot override those settings.
Posting runs with Shell's UID (2000); collectors and evidence remain root-only.
The primary-user notification record is checked for the incident ID after posting,
rather than treating a successful command exit as proof of delivery. This is
validated on user 0; other foreground Android users are not currently supported.

The watcher cannot reconstruct events from before installation. Its two-second
sampling may miss intermediate state changes, although PID changes and continuous
logs usually preserve the useful evidence. It cannot guarantee capture of every
failure, especially a reboot/power loss or rapid sequence that wraps the buffers.
No signal-sender tracing is enabled; an external killer may remain unidentified.

## Privacy

Data stays under `/data/adb/a11-fingerprint-monitor` (root-only directory, mode
0700; files created with umask 077). No network functionality. No app databases,
fingerprint-template files, PIN/pattern, authentication keys, or `/proc/*/mem` are
read. Verbose `cdfingerTA` logs are deliberately excluded. Main log selection is
restricted to diagnostic/error messages from selected system/vendor tags; kernel
payload-oriented messages are filtered out. **These are still raw vendor/system
diagnostics and can contain private metadata** such as template IDs, paths, UIDs,
or package names. Review/redact incident bundles before publishing or sharing.
Do not commit them to this repository.

## Build / install

```sh
make monitor
adb push dist/a11_fingerprint_monitor-v1.0.0.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/a11_fingerprint_monitor-v1.0.0.zip'"
```

Normally starts automatically after the next boot. A newly installed module is
staged at `/data/adb/modules_update/a11_fingerprint_monitor`; to start immediately
without rebooting, run its `control.sh start` there. Do not move staged modules
yourself. After reboot, use `/data/adb/modules/a11_fingerprint_monitor` instead.

Examples after boot activation:

```sh
adb shell "su -c 'sh /data/adb/modules/a11_fingerprint_monitor/control.sh status'"
adb shell "su -c 'sh /data/adb/modules/a11_fingerprint_monitor/control.sh self-test'"
adb shell "su -c 'sh /data/adb/modules/a11_fingerprint_monitor/control.sh capture'"
```

Magisk's **Action** button requests a manual capture; it does not restart anything.
The self-test is explicitly labeled simulated and posts a test notification.
Read `latest-incident`, then `incidents/<ID>/summary.txt`; wait for its completion
line before copying the whole bundle. The notification is sent once initial
context is safely stored, before follow-up diagnostics finish.

Validation on the target phone: live collectors, singleton startup, clean stop,
root-only files, completed simulated incident snapshots, and the actual updated
notification record were checked without rebooting or restarting the fingerprint
HAL. Local tests exercise detection logic, rotation, retention, permissions, safe
command quoting, and reproducible packaging.

Automatic startup across a full reboot was then verified: the daemon started
after boot completion, established the live HAL PID as its baseline, and correctly
captured the shutdown that preceded the next reboot as a `hal-lifecycle-change`
incident. That incident's notification failed because the phone was already
shutting down, which is expected. One rough edge was observed: while the system
was shutting down, the daemon restarted its logcat collector a few times in quick
succession. It is harmless, but a future revision could stop restarting
collectors once a shutdown is in progress.

The monitor also proved useful during that reboot: it recorded the HAL's
post-reboot startup, including the `Can't open silead HW Module, error: -22`
message from the paired workaround module, and the complete absence of Silead
kernel-driver messages for that boot.

## Stop / remove

Disable in Magisk to stop within a polling cycle; an in-progress diagnostic may
take a few more seconds to terminate. Or run `control.sh stop`. Disabling prevents
automatic startup on subsequent boots. Uninstall also stops the monitor, but
**retains the evidence** so uninstalling cannot erase the explanation for a fault.
After reviewing/backing up the evidence, its one private directory may be removed
manually if no longer wanted. Removing this monitor does not remove the fix.

No kernel trace state or external boot script needs cleanup. The last notification
may remain until dismissed. Disable/remove before changing to unvalidated firmware.
