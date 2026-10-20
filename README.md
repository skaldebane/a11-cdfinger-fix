# Galaxy A11 cdfinger Fix

A small, systemless Magisk module that avoids a failed-probe cleanup hang in the
Samsung Galaxy A11 fingerprint HAL. **It does not bypass biometric authentication.**

An optional, separate [passive diagnostic monitor](monitor/README.md) captures HAL
restarts/errors and posts local incident notifications. Build it with `make monitor`.
It is not bundled with or required by the workaround.

## Supported configuration

Installation is restricted to the configuration on which recovery was tested:

- Galaxy A11, device `a11q` (tested on SM-A115F).
- Android 12 / API 31.
- Vendor build fingerprint:
  `samsung/a11qnsxx/a11q:12/SP1A.210812.016/A115FXXU3CVI3:user/release-keys`.
- Previously detected sensor: `persist.vendor.runin.fp=cdfinger`.
- Magisk 20.4 or newer (installation tested with Magisk 31.0).

Do not remove these checks to install on Silead-equipped phones. A model name
alone does not establish the sensor variant. Other firmware is untested.

**Disable/remove this module before upgrading firmware.** Compatibility is checked
at installation and when running the optional action, not at every boot. The static
overlay remains active until the module is disabled/removed and the phone reboots.

## What actually goes wrong

Two separate failures have to line up before the sensor becomes unusable. This
section documents both, because the fix only addresses the second one.

### 1. The fingerprint HAL can exit on a secure-world error

The installed vendor library `/vendor/lib/hw/cdfinger.fingerprint.default.so`
contains an unconditional process exit on a failed secure-world command. In
`cfp_ta_send_command()`, a non-zero return from `QSEECom_send_cmd()` is logged as
`Failed to send cmd[%d], ret = %d` and then reaches `exit(0)`.

That ends the **entire HAL process**, not just the in-flight request, and it is a
normal `exit()` rather than a fatal signal, so it leaves no tombstone or crash
entry behind. `init` then restarts `vendor.fps_hal`. A second `exit(0)` exists on
the fingerprint close path, which likewise produces no crash record.

This is a candidate explanation for the *first* event in the chain: a transient
secure-world error kills a working HAL. It was not proven as the cause of any
particular historical occurrence, because the logs from that event had already
rotated away. The monitor watches for the `Failed to send cmd` message so this
becomes observable the next time it happens.

### 2. A restart is what turns that into a permanent outage

The HAL's startup probes vendor implementations in a fixed order — Silead, then
cdfinger, then Focaltech, then Egis — and continues to the next one when a
module fails to open.

On a cold boot that order is harmless: cdfinger's kernel driver has not claimed
the interrupt yet, so the HAL reaches cdfinger directly.

After a **restart**, the situation is different. cdfinger's kernel driver still
owns the interrupt, and Silead's probe cannot get it. The kernel log on the
affected device shows:

```
genirq: Flags mismatch irq 155. 00000001 (silfp) vs. 00000001 (cdfinger_eint)
[+silead_fp-] [silfp_resource_init] Filed to request_irq (155), ert=-16
```

`-16` is `-EBUSY`. Both drivers request the same GPIO 48 interrupt without
`IRQF_SHARED`, so the request is exclusive. The device tree confirms both
implementations describe the same pins (IRQ GPIO 48, reset GPIO 140).

The HAL nevertheless continues, and Silead's cleanup path then blocks forever:
the main thread sits in `silfp_nl_deinit()` → `pthread_join()` while its worker
sits in `_thr_read()` → `poll()` with an infinite timeout. Startup never reaches
cdfinger, so the HAL never registers with Android.

Why the cleanup hangs is explained by the public A11 kernel source for this
platform family ([JustForkin/android_kernel_samsung_a11q](https://github.com/JustForkin/android_kernel_samsung_a11q),
commit `8e4db55`), whose Silead driver version matches the one the HAL reports.
There, the Silead `INIT` ioctl calls `silfp_resource_init()` but **ignores its
return value**, and `silfp_resource_deinit()` only posts the disconnect/wakeup
message inside `if (atomic_read(&fp_dev->init))`. When the IRQ request failed,
that flag was never set, so cleanup never notifies the userspace reader that is
blocked in `poll()` waiting for exactly that message.

The observed userspace stacks are direct evidence; the kernel-side state
transitions are inferred from this closely matching reference implementation
rather than from instrumenting the running driver.

### The symptoms this produces

- Android reports `Fingerprint HAL not available` and falls back to
  pattern/credential, because the fingerprint service is not registered at all.
- Authenticators that require a strong biometric cannot be satisfied by a
  pattern, so those apps become unusable until the HAL recovers.
- The lock screen may still mention fingerprint, since enrollment metadata and
  current HAL availability are separate things.
- A **full reboot** fixes it: it resets the kernel-side allocations that the
  stale Silead probe collides with. A framework-level soft restart does not.

## What this module does

The module contains exactly one replacement library:

```
system/vendor/lib/hw/fingerprint.silead.default.so  # intentionally ZERO bytes
```

Magisk overlays this file at `/vendor/lib/hw/fingerprint.silead.default.so`.
The dynamic loader rejects the empty file immediately, without running any
Silead code, so the failed probe never happens and the HAL proceeds to cdfinger.
cdfinger then uses the real sensor, existing enrollments, and normal
authentication checks. Original vendor-partition files are not modified.
Missing/invalid Silead library errors in logcat are expected.

There is no boot script, polling daemon, SELinux-policy patch, property spoofing,
or automatic HAL restart. Magisk applies the overlay before normal HAL startup.

This removes the failure that makes a restart permanent. It does **not** remove
the secure-world error that may kill the HAL in the first place; that error is
diagnosed and handled by the optional monitor, not fixed.

## Verification on the target device

After a full reboot with this module active:

- The Silead library is masked to zero bytes, and the HAL logs
  `Can't open silead HW Module, error: -22` before `cdfinger module is working...`.
- The count of Silead IRQ/probe messages for that boot is **zero** — Silead never
  reached the kernel driver, so the conflict in section 2 cannot occur.
- cdfinger initializes the sensor, reads chip id `0x88`, and allocates its IRQ
  cleanly.
- `android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint/default`
  is registered, `HAL deaths since last reboot: 0`, and all three previously
  enrolled fingerprints are still present.
- Fingerprint authentication was confirmed working by the device owner.

## Build and test

Requires Python 3 and Make; no third-party Python packages or downloads.

```sh
make
```

Output:

```
dist/a11_cdfinger_fix-v1.0.1.zip
dist/a11_cdfinger_fix-v1.0.1.zip.sha256
```

The ZIP has module files at its root and reproducible timestamps/permissions.
This is a standard **Magisk app/CLI installer**, not a recovery-flashable ZIP;
`META-INF` is unnecessary for app/CLI installation under Magisk's documented format.

## Install

In Magisk, select **Modules → Install from storage**, choose the built ZIP, and
reboot when convenient. Or, from an authorized ADB host:

```sh
adb push dist/a11_cdfinger_fix-v1.0.1.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/a11_cdfinger_fix-v1.0.1.zip'"
```

Installation alone does not activate newly staged Magisk mounts or restart any
service. A reboot is required for the overlay to be applied at boot.

After normal activation, Magisk's optional **Action** button requests a restart
of only `vendor.fps_hal`, useful if recovery is needed without rebooting. It first
checks compatibility, module status, and that the Silead path is an empty file.
It does not itself mount anything or confirm a successful fingerprint match.

## Verify

```sh
adb shell "su -c 'ls -l /vendor/lib/hw/fingerprint.silead.default.so'"
adb shell "su -c 'lshal 2>/dev/null | grep android.hardware.biometrics.fingerprint'"
adb shell dumpsys fingerprint
```

The Silead file should have size 0. The standard
`IBiometricsFingerprint/default` interface should be registered. Finally, test an
actual fingerprint authentication on the phone; service registration alone is
not an end-to-end authentication test.

## Disable / uninstall

Disable or remove **Galaxy A11 cdfinger Fix** in Magisk, then reboot. Magisk removes
its systemless overlay; the original vendor library becomes visible again. No
fingerprint enrollment is removed, and there are no external boot scripts or
security-policy changes to clean up.

If a new module ever prevents normal boot, use your root manager's module-safe-mode
procedure or recovery to create `/data/adb/modules/a11_cdfinger_fix/disable`, then
reboot. The overlay targets only an unused fingerprint implementation, but keep a
working PIN/pattern and recovery access as with any systemless module.

## References

- [Magisk developer guides](https://topjohnwu.github.io/Magisk/guides.html)
- [A11 kernel source (Silead + cdfinger drivers)](https://github.com/JustForkin/android_kernel_samsung_a11q)
- [Similar Android 12 / One UI 4.1 symptom reports](https://eu.community.samsung.com/t5/galaxy-a-series/fingerprint-not-working-after-android-12-one-ui-4-1-update/td-p/5800610)

Those public reports describe similar symptoms but do not establish this native
failure; the workaround was derived from native backtraces, the kernel driver's
own error messages, and controlled tests on the device. The full investigation
log, including backtraces and device state dumps, is deliberately kept out of this
repository because it contains device-specific logs.

## License

MIT. No proprietary vendor binaries or private device logs are included.
