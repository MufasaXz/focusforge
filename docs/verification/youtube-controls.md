# YouTube controls and leaderboard corners

This follow-up supersedes the educational-creator filtering described in account-recovery.md. At the user's request, the YouTube tab keeps its logo/name and the Shorts, home/search and conditional focus-only switches. It has no study-channel control, manual creator manager or whole-app shortcut. The subsequent screenshot request restores the former outlined Shorts recognition note beneath the switches, using the existing translations. Whole-app rules remain available through Apps.

The retired study filter is removed from Dart/native rules, status counts and enforcement. Both parsers ignore its legacy cached fields, so an existing installation or native service restart cannot keep an invisible filter active. Accessibility scans read resource identifiers and visibility without creator text. Native settings and in-app consent describe the remaining Shorts/feed checks.

Leaderboard rows are inset eight logical pixels inside their outer card. This contains the row's sixteen-pixel corner arcs within the card's twenty-four-pixel clip, preserving the gold own-row outline at the bottom and top of the list. Normal surface colours and existing compact/large-text behavior remain.

Verification:461Flutter tests passed;65Android tests passed (includes three unrelated workspace tests excluded from the commits;62tests in committed source); analyzer reports no issues; localization generator and four focused localization tests pass after final native-summary regeneration. No Firestore changes were needed. Independent read-only review found no concrete remaining issue.

Dart/native legacy-rule tests and bottom-corner containment tests failed before the fixes and passed afterward. Existing native tests cover Shorts precedence, visible resource matching, ordinary playback, live settings, focus expiry and grace. The corner regression exercises both light and dark themes at320dp/2x text.

Evidence is stored outside the repository under focusforge-work-files/youtube-ui-final-2026-10-16. Real-device visual and YouTube runtime validation were not performed in this pass.
