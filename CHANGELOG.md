# Changelog

## 1.0.3 — 2026-10-10

Android build 2011.

### Added

- Retro countdown dial in the Focus tab, full-screen clock and clock picker.
  New installs use Retro; existing clock selections stay saved.
- Parchment palette with warm ivory day surfaces and charcoal dark surfaces.
  New installs follow system brightness and use normal dark mode; true black
  remains available in Appearance.
- Android home-screen widget with a native live countdown, today's completed
  focus minutes and a shortcut to Focus. The widget reads the same local timer
  deadline and session log as the app, and follows the saved theme and palette.

### Improved

- Frosted cards, soft shadows, gradient edges and floating pill navigation
  throughout the app, including study groups and parent screens.
- Appearance settings explain how to add the Android widget.

### Fixed

- Full-screen day mode no longer uses a black background when the saved
  true-black preference is enabled.
- Chart day labels stay within their slots on narrow screens.
- Recovered sessions stop reading providers if the container is disposed while
  a save is in progress.

### Release details

- Version 1.0.3 (2011), signed with the existing Android release certificate.
  The build number exceeds the earlier architecture-specific version codes.
- Release packaging was rebuilt from a clean workspace so every CPU
  architecture includes the current compiled app.
- Validation: 220 Flutter tests passed, static analysis reported no issues,
  and day/dark screen captures passed. The Android build and v1/v2/v3
  signatures were verified. Phone installation and launcher behavior still
  need device confirmation; the server emulator failed to initialize its
  storage service for both the earlier and new APKs.

## 1.0.2 — 2026-10-09

Android build 9.

### Added

- A seven-day recap on You, showing completed focus time, active days and
  daily-goal editing, plus shortcuts to Focus and Shield.
- Shield filters for blocked, focus-only and budgeted apps. Search now matches
  package names as well as app names; empty results offer a single reset action.

### Improved

- Redesigned login and setup with a focus preview, tonal surfaces, clearer
  account benefits, refined typography and selected-state styling.
- Refreshed profile identity and Shield overview with theme-aware accents and
  rule counts. The overview explains when Android accessibility is required.
- Shield headers adapt to enlarged text, including the parent's child selector.

### Fixed

- Email sign-in explains whether credentials are local or handled by Firebase.
- Unexpected sign-in failures release the loading state and allow another try.

### Release details

- Version 1.0.2 (9), signed with the existing Android release certificate.
- Existing blocking, YouTube filtering, study groups and parent features remain
  available. Cloud features still require the existing Firebase configuration
  and Firestore rules; see [Firebase setup](docs/firebase-setup.md).
- This UI release does not change Play Protect eligibility; see
  [installation and review guidance](docs/play-protect.md).

## [1.0.1](https://github.com/MufasaXz/focusforge/releases/tag/1.0.1) — 2026-10-08

Android build 8. Changes since 1.0.0.

### Added

- Private study groups with invite codes, shared weekly goals, member standings,
  focus status and ownership transfer when the owner leaves.
- Parent pairing, child study summaries and remote distraction rules. Parent
  devices get a focused three-tab layout and a child selector.
- Editable daily goals, a daily progress ring, day-by-day session history and
  a monthly top-subject card.
- Focus-only app blocking and controls to adjust a session by five minutes.

### Improved

- Setup screens, dashboard hierarchy, settings layout, typography, card shapes
  and spacing across phones and tablets.
- Start/Pause controls, named ambient sounds and shared animated selectors.
  Press feedback and transitions respect reduced motion.
- Native Shield messages with a clearer blocking reason, app icon and actions.
- The 4–7–8 breathing guide with phase countdowns, gentle transitions, an early
  return action and recovery when opening an app fails.
- Optional accessibility disclosure before opening Android permission settings.
- README with the app logo, four current screenshots and a Focus animation.

### Fixed

- Shield rules that could stop applying and parent rules that could disappear
  after an offline restart or failed read.
- Parent pairing and unlink operations now update related records atomically;
  used or expired pairing codes are rejected.
- Blank profile/parent views after denied cloud reads, and misleading feedback
  when saving parent rules fails.
- Narrow preset layouts, large-text setup screens, small focus-total rounding
  and chart accessibility.
- Missing icon boxes in README screenshots by loading the bundled icon font
  during capture.

### Release details

- Download: `focusforge-1.0.1.apk` (Android 7.0+, ARM32, ARM64 and x86_64).
- Smaller `arm64-v8a` (ARM64), `armeabi-v7a` (ARM32) and `x86_64` APKs are
  available in the same release alongside the universal APK.
- Uses the existing release certificate; v1, v2 and v3 signatures are included.
- Groups and parent sync require the current [Firestore rules](docs/firebase-setup.md).
  Production rules have not been deployed from this workspace. Both devices
  should update before using the new pairing/unlink flow.
- Accessibility-based blocking can still trigger Play Protect restrictions.
  This release improves disclosure but does not guarantee scanner approval; see
  [installation and review guidance](docs/play-protect.md).

[Compare with 1.0.0](https://github.com/MufasaXz/focusforge/compare/1.0.0...1.0.1).

## [1.0.0](https://github.com/MufasaXz/focusforge/releases/tag/1.0.0) — 2026-10-07

Initial Android release with app shielding, YouTube surface filtering,
Pomodoro and custom plans, ambient audio, full-screen clocks, local study
analytics, streaks, XP and badges.
