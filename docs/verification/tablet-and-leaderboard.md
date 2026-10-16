# Tablet layout and leaderboard refresh

The tablet shell uses a compact floating rail centered within system-safe bounds. Landscape Focus puts the timer and its session controls beside an independently scrolling ambient panel. Home places weekly history beside today's overview and subject breakdown; without history it centers a readable single column. Profile moves community actions beneath the identity card and keeps preferences alongside it. Screen breakpoints use the space available after the rail. Phones retain their single-column layout and bottom navigation.

Leaderboard now renews its subscription on page entry, foreground return and pull-to-refresh, and requests publication of the signed-in account's opted-in score. Failed reads reconnect after 2, 5 and eventually 15 seconds. Subscription and retry lifetimes are tied to the account, week and provider. Previous rows are explicitly cleared before loading a replacement, including Riverpod's retained-value behavior. No sharing-consent or signout-retention policy changed.

Validation on 2026-10-16:

- 477 Flutter tests passed. Regressions cover failed-read recovery without reopening, first entry/resume/manual refresh, pending-retry cancellation across accounts, successful old rows followed by delayed replacement/error, floating navigation in landscape and portrait, short windows with large text, Focus panel/control placement, and fresh/inactive-week Home layout.
- Flutter analyzer reports no issues; formatting and diff whitespace checks pass.
- Current screens captured in both themes at 1280 × 800, plus portrait at 800 × 1280, with bundled fonts and fictional local data. Capture harness asserts no widget exceptions.
- Independent read-only review found stale retained rows and an empty history column; both findings were resolved and reviewed again with regression coverage.
- Signed AAB/APK built with the existing optimized release configuration, version 1.0.0 and build code 2023. Mapping and native symbols are extracted from the exact AAB, with signature, bundle structure, ZIP integrity and native alignment/Build ID checks recorded alongside delivery artifacts.

Reproduce the tablet artwork with `flutter test tool/capture_tablet_test.dart` followed by `python3 tool/compose_tablet_promos.py`. Four 2560 × 1600 PNGs use actual app captures at their original aspect ratio, a neutral tablet frame and the supplied dark green/cream/gold direction. The output includes source hashes.

Evidence lives outside Git under `projects/focusforge-work-files/tablet-final-2023`; delivery files are under `projects/deliveries/focusforge-tablet-final-2023`. This pass uses widget renders rather than a physical tablet. Live Firebase connectivity and Play Console processing were not exercised. The software emulator was unstable at the Android system level, so no successful emulator interaction is claimed. Upstream AndroidX DataStore ships a pre-stripped native library without matching debug symbols; the nine app/Flutter/Dart JNI symbol files are supplied.
