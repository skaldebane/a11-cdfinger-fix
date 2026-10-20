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

## Why it works

The installed fingerprint service probes Silead before cdfinger. On the affected
device, Silead initialization fails and cleanup blocks in `silfp_nl_deinit()` /
`pthread_join()`, while its worker waits indefinitely in `poll()`. Startup never
reaches the actual cdfinger sensor or registers the fingerprint HAL with Android.

The module contains exactly one replacement library:

```
system/vendor/lib/hw/fingerprint.silead.default.so  # intentionally ZERO bytes
```

Magisk overlays this file at `/vendor/lib/hw/fingerprint.silead.default.so`.
The dynamic loader rejects the empty file immediately, without running any Silead
code. The service proceeds to cdfinger, which uses the real sensor, existing
enrollments, and normal authentication checks. Original vendor-partition files
are not modified. Missing/invalid Silead library errors in logcat are expected.

There is no boot script, polling daemon, SELinux-policy patch, property spoofing,
or automatic HAL restart. Magisk applies the overlay before normal HAL startup.

This addresses the confirmed recovery hang. It does not explain or necessarily
prevent the event that originally terminated the working fingerprint service.
The temporary equivalent restored fingerprint authentication without a reboot;
the user confirmed successful authentication. Module behavior across a full
reboot still needs to be verified separately.

## Build and test

Requires Python 3 and Make; no third-party Python packages or downloads.

```sh
make
```

Output:

```
dist/a11_cdfinger_fix-v1.0.0.zip
dist/a11_cdfinger_fix-v1.0.0.zip.sha256
```

The ZIP has module files at its root and reproducible timestamps/permissions.
This is a standard **Magisk app/CLI installer**, not a recovery-flashable ZIP;
`META-INF` is unnecessary for app/CLI installation under Magisk's documented format.

## Install

In Magisk, select **Modules → Install from storage**, choose the built ZIP, and
reboot when convenient. Or, from an authorized ADB host:

```sh
adb push dist/a11_cdfinger_fix-v1.0.0.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/a11_cdfinger_fix-v1.0.0.zip'"
```

Installation alone does not activate newly staged Magisk mounts or restart any
service. When installed during the original investigation, the equivalent live
mount was already active, so no immediate reboot was needed to retain recovery.

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

The manually applied investigation mount is separate from Magisk's boot mounts.
If it is still present during the installation session, it also disappears on
reboot. Do not blindly unmount paths after boot: let Magisk remove its managed
mounts by disabling/removing the module and rebooting.

If a new module ever prevents normal boot, use your root manager's module-safe-mode
procedure or recovery to create `/data/adb/modules/a11_cdfinger_fix/disable`, then
reboot. The overlay targets only an unused fingerprint implementation, but keep a
working PIN/pattern and recovery access as with any systemless module.

## References

- [Magisk developer guides](https://topjohnwu.github.io/Magisk/guides.html)
- [Similar Android 12 / One UI 4.1 symptom reports](https://eu.community.samsung.com/t5/galaxy-a-series/fingerprint-not-working-after-android-12-one-ui-4-1-update/td-p/5800610)

Those public reports do not establish this exact native failure; this workaround
was derived from native backtraces and a successful controlled test on the device.

## License

MIT. No proprietary vendor binaries or private device logs are included.
