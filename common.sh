#!/system/bin/sh

# Installation and the optional recovery action share the same narrow gate.
check_compatibility() {
  [ "$(getprop ro.product.device)" = a11q ] || {
    echo 'Unsupported device: expected Galaxy A11 (a11q).'
    return 1
  }
  [ "$(getprop ro.build.version.sdk)" = 31 ] || {
    echo 'Unsupported Android version: expected Android 12 (API 31).'
    return 1
  }
  [ "$(getprop ro.vendor.build.fingerprint)" = \
    'samsung/a11qnsxx/a11q:12/SP1A.210812.016/A115FXXU3CVI3:user/release-keys' ] || {
    echo 'Unsupported vendor firmware: expected A115FXXU3CVI3.'
    return 1
  }
  [ "$(getprop persist.vendor.runin.fp)" = cdfinger ] || {
    echo 'Unsupported sensor configuration: expected previously detected cdfinger.'
    return 1
  }
}
