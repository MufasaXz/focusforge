# Changelog

## Unreleased

- Shield now offers every app that has a launcher icon, so a preinstalled
  browser, mail client or video app can be restricted like any other. Those
  were previously hidden for being system apps, which left most of what a
  student actually wants to close missing from the list with nothing on screen
  to say why.
- Fixed today's focus minutes, today's goal, the streak, the heatmap, the top
  subject and the per-subject counters holding yesterday's numbers when the app
  was left open past midnight — the chart beside them had already rolled over,
  so the same screen disagreed with itself.
- The subject ring no longer splits itself evenly between subjects on a day
  with nothing on it yet. An empty day reads as empty rather than as a finished
  one, which is what it looked like every morning.
- Edge-to-edge is now set up with current APIs rather than through
  `WindowCompat.enableEdgeToEdge`, whose unguarded `setStatusBarColor` and
  `setNavigationBarColor` calls Play Console reports as deprecated. The bar
  colours below Android 15 come from the window theme instead, so they also
  apply to the launch window before the first frame.
- FocusForge now asks before it reads the list of installed apps or per-app
  usage. The Shield tab shows the disclosure in place of the list, usage
  access asks first, and Profile → Privacy can withdraw it. Until the user
  agrees, nothing reads the list; it never leaves the device either way.
- Removed the parts of the bundled usage-statistics plugin the app never
  used — network, storage and configuration statistics, and app version and
  install-time details.
- Firestore no longer accepts client writes to the user's root document. No
  current feature wrote it; parent control was the last.

## [1.0.4](https://github.com/MufasaXz/focusforge/releases/tag/1.0.4) — 2026-10-24 (build 2029)

- Rebuilt the Neon clock face as lit tubing — a white-hot core over a coloured
  halo that reads as a tube on dark panels.
- Turned the Clock face picker into a preview: the selected face fills a tinted
  hero at reading size, and the rest sit in a two-column grid of live clocks.
- Added a podium for the leaderboard's top three and lit status dots for
  members who are focusing right now.
- Gave each preset a rhythm bar in the plan picker, so a plan's focus/break
  split is readable without parsing numbers.
- Folded the Focus tab's daily tally into a goal card with a progress ring.
- Refined the subject breakdown ring — selected slices lift with rounded caps
  and a sheen, and the centre reads the share as a percentage.
- Simplified Account & privacy into grouped, tappable rows with a single
  account summary at the top.
- Fixed the displayed app version being a release behind the build, and capped
  display names at the 60-character limit the leaderboard enforces.

## [1.0.4](https://github.com/MufasaXz/focusforge/releases/tag/1.0.4) — 2026-10-19

- Improved account recovery with automatic retries and clearer progress while saved study data returns.
- Restored saved subjects, custom plans, goals, completed sessions and achievements after signing in again.
- Kept existing logins and study setup across app updates, with background syncing.
- Improved leaderboard refresh, personal ranking, level display and sharing controls.
- Added profile photos and synced name and photo changes with the current weekly leaderboard.
- Added automatic language detection with support for 25 languages.
- Added responsive tablet layouts and floating side navigation.
- Simplified setup with clearer steps, shorter instructions and better selection states.
- Added subject management with matching icons, distinct colors and removal controls.
- Improved the Home timer shortcut and subject-time breakdown.
- Added random focus blocks and more reliable recovery of interrupted sessions.
- Fixed long-duration and hour timers overflowing compact and flip-clock layouts.
- Refined Shield pause screens and improved supported YouTube Shorts and feed detection.
- Fixed Google sign-in configuration being removed from optimized releases.
- Refreshed app screenshots and added Play Store testing and GitHub download links.

## 1.0.0 first Play release candidate — 2026-10-14

Android build 2022 retains the existing signing identity and increasing version
code. The display version starts at 1.0.0 for the first Play submission.

- Refined setup with a real retro timer preview, suggested and named custom
  plans, clearer steps, solid action surfaces and account-scoped draft resume.
- Removed the Shield activation banner and app-count label. Permission requests
  remain tied to feature activation; both app blocking and YouTube filtering
  require Accessibility in the current engine. Removed unused DND access.
- Added a weekly progress launcher widget with Monday–Sunday focus totals.
  Refined all widgets with consistent fonts, responsive spacing, day/dark/AMOLED
  styling and a retro dial matching the app. Counts use completed owned sessions.
- Added four intermediate achievements, an always-available next milestone,
  real remaining units, newest-earned ordering and responsive collection/details.
  Existing badge IDs and earned dates remain intact.
- Updated private badge rules for all 18 IDs while preserving ownership, valid
  dates and existing earns within Firestore evaluation limits. Publish the revised
  rules for new badges to sync. Production backend changes were not deployed here.

Play submission still needs deployed backend/policy pages, Accessibility
declaration and review video, accurate Data safety and real-device verification.

## 1.0.3 achievement backup — 2026-10-13

Android build 2019. Replaces the downloadable APK on the existing 1.0.3 release.

- Earned badge IDs and original earned dates now back up privately to a linked
  Firebase account. Signing out does not delete them; the same account can
  recover them months later or on another device after the first online sync.
- Offline unlocks remain local and retry automatically. The achievement page
  shows whether backup is saved, syncing or waiting, with a manual retry.
- Concurrent devices merge earned badges without removing existing unlocks.
  Account changes restore separate cabinets and measure only owned sessions
  and breath events; a first guest link keeps that guest's earns.
- Account deletion removes the private cloud cabinet and drains local writes
  before wiping data. Detailed session logs and setup still stay on-device.
- Added private owner-only achievement rules and regression tests. Publish the
  complete revised firestore.rules to enable cloud backup; production rules
  have not been deployed here.

Validation: 281 Flutter tests and 24 local Firestore rules tests passed; static
analysis clean. Production Firebase restore still needs runtime verification.

## 1.0.3 refresh — 2026-10-12

Android build 2018. Replaces the downloadable APK on the existing 1.0.3 release.

- Restored the earlier frosted Home, YouTube and Focus surfaces while keeping
  varied solid cards elsewhere. Neutral day/dark surfaces remove the yellow
  cast while retaining the selected accent. Tuned setup summary tile colors.
- Simplified You: removed Shield/Focus shortcuts and weekly progress; kept
  identity, achievements, appearance and clearly grouped preferences.
- Added a discoverable Account & privacy page with sign-out, return greetings,
  and confirmed account deletion with email/Google reauthentication. Completed
  local profiles skip onboarding on sign-in and keep their focus history.
- Account deletion removes group memberships, parent links, shared summaries
  and board weeks known to this device before deleting the Firebase credential.
  Failures preserve the credential and local history for retry. Remote records
  from other devices need backend cleanup; see Firebase setup documentation.
- Redesigned App access with plain permission explanations, accessibility setup
  instructions, retry states and a settings entry available after onboarding.
  Removed the timer-ready banner. Local Shield enables now explain and request
  missing accessibility/usage access before activating a rule.
- Added an ongoing system countdown for running focus/break timers, including
  eligibility for supported Android 16/OEM live bars. Actual promotion depends
  on device software and notification settings.
- Fixed blank/white widget previews, added compact widget layouts, theme-aware
  backgrounds and resizing/font-scale handling; corrected countdown formatting.
- Fixed missing Material ancestry in settings dialogs and large-text overflows
  in permission guidance and the dashboard goal ring.

- Added multiple named custom Pomodoro plans, edit/remove controls, removable
  stock plans and default restoration. Stable plan identities preserve running
  timers when other presets are removed; unfinished current changes confirm.
- Disabled Android backups and cleartext traffic, redacted timer subjects on
  sensitive lock screens, and constrained YouTube accessibility inspection.
- Removed real Firebase client configuration from tracked source. Historical
  client identifiers remain public; no administrator/signing secrets were found
  by the 209-commit history scan. Key revocation/restrictions need project admin.
- Hardened local Firestore rules and pairing tokens, removed persistent shared
  cache, cleared retained family/group views on identity changes, reset board
  consent for new accounts, and removed credentialless account-link claims.

Validation: 271 Flutter tests and 18 local Firestore rules tests passed; static
analysis clean. Signed release APK built with valid v2/v3 signatures and the
existing certificate. Merged manifest confirms disabled backup/cleartext.
The day/dark/tablet UI render capture harness also passed.

Production rules were not deployed. New pairing needs the revised rules and
both devices on this build. See docs/firebase-setup.md and the security audit.
Device-native live bars/widgets and real Firebase login/deletion still require
runtime verification; no successful physical-device/emulator QA is claimed.

## 1.0.3 — 2026-10-11

Android build 2016.

- Refreshed weekly leaderboard standings, study groups, profile identity and
  insights, settings, parent controls and child progress with responsive glass
  cards and clearer hierarchy.
- Stabilized floating navigation pill transparency during tab transitions and
  added layout regression coverage. Physical-device flash elimination has not
  been verified.
- Updated the GitHub gallery with four phone-only light-theme app renders.
  All sample study and profile data is fictional.

- Setup flow polish: frosted pinned footer, per-stage progress stepper,
  product promise on the splash, and a tonal celebration hero. Guardian and
  student branches unchanged.
- Seventh clock face, Serif: remaining time in the bundled FocusDial serif
  with an InterDisplay colon, in the Focus tab, full-screen clock and picker.
  Existing clock selections stay saved.
- Launcher widgets declare picker previews on Android 12+, and the
  daily-goal ring track follows the saved palette.

- Restored the original InterDisplay clock, numbered minute marks, shaded rim
  and progress hand in the app. Retained the improved launcher widgets and
  clean sign-in screen.

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

### Earlier build-2015 validation (historical)

The following checks describe the previous build, not final build 2016.

- Version 1.0.3 (2015), signed with the existing Android release certificate.
  The build number exceeds the earlier architecture-specific version codes.
- Wave-2 premium changes in this build: setup polish (chrome, flow, splash,
  celebration) and the Serif clock face plus widget previews (Kotlin, XML,
  faces, picker, tests).
- Validation: 226 Flutter tests passed, static analysis reported no issues,
  and day/dark/tablet captures regenerated. The Android release build and
  v1/v2/v3 signatures were verified; the APK was uploaded for device
  confirmation.

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
