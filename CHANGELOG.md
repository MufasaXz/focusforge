# Changelog

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
