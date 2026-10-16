# Local Android build compatibility patch

Source: usage_stats 2.0.1 from https://pub.dev/packages/usage_stats and
https://github.com/Parassharmaa/usage_stats, licensed under MIT (see LICENSE).
Dart and native runtime sources are unchanged.

The Android Gradle script uses the host AGP 9 built-in Kotlin support, removes
the external Kotlin plugin/buildscript and redundant repository declarations,
and preserves JVM 17 and the upstream runtime dependency versions. The package
manifest omits screenshots excluded from this source distribution. Revisit this
path dependency when upstream supports built-in Kotlin.
