# Local Android build compatibility patch

Source: usage_stats 2.0.1 from https://pub.dev/packages/usage_stats and
https://github.com/Parassharmaa/usage_stats, licensed under MIT (see LICENSE).
Dart and native runtime sources are unchanged.

The Android Gradle script uses the host AGP 9 built-in Kotlin support, removes
the external Kotlin plugin/buildscript and redundant repository declarations,
and preserves JVM 17 and the upstream runtime dependency versions. The package
manifest omits screenshots excluded from this source distribution. Revisit this
path dependency when upstream supports built-in Kotlin.

## Removed upstream API (FocusForge 2026-11)

Play's User Data policy treats the installed-app list as personal and
sensitive data. The plugin is cut down to the five calls FocusForge makes —
`isUsagePermission`, `openUsageAccessSettings`, `queryEvents`,
`queryInstalledApps` and `getAppIcon` — and `queryInstalledApps` now returns
only the package name, label and system flag. Removed: network and storage
statistics (`NetworkStats.kt`, `StorageStats.kt`), configuration, event and
aggregated usage statistics, standby bucket and inactivity checks,
`getAppInfo`, `grantUsagePermission`, `queryEventsForSelf`, and the version and
install-time fields. The Dart and native runtime sources are therefore no
longer upstream's; the sentence above that says they are unchanged applies to
the build-script patch only.
