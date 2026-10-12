# FocusForge refinement implementation plan

**Goal:** Polish the app, publish a verified Android 1.0.3 replacement, then produce a promo using the updated app.

**Architecture:** Retain Flutter/Riverpod and existing native Shield. Use solid tonal cards for content, open layouts for identity, and restrained glass for floating chrome. Keep timer and notification state derived from the same persisted countdown.

**Constraints:** Preserve local history and pending user changes; Android 7+; no Firebase rules deployment; honest device-dependent dynamic bar support; accessible layouts at 320dp and 2× text; app work and release before promo production. Main push and release asset replacement are explicitly requested.

- [ ] Account task (`auth_returning_and_deletion`): returning sign-in recognizes completed setup and welcomes by name, preserves settings/history, deletion is clearly reachable and safely cleans credentials/cloud/local state. Own auth services, auth screen, privacy screen, account provider changes and related tests.
- [ ] Android task (`android_widgets_live_activity`): fix initial widget presentation, theme and resizing; add genuine ongoing focus notification with native countdown, subject, progress, tap to open, removal on stop. Own Android files and widget/activity bridges; report any Dart timer hook needed.
- [ ] UI task (root): remove Shield/Focus shortcuts and weekly overview/goals from You; expose account controls; redesign permissions with clear benefit/status/steps and resilient error handling; vary surfaces; polish typography/navigation and small/large screen behavior.
- [ ] Run focused regressions, full Flutter tests/analyze, native APK build, signed certificate and version checks, emulator screenshot and interaction QA; resolve failures before publishing.
- [ ] Commit requested app changes and push HEAD to main without force. Replace release `1.0.3` APK and SHA256 after verification, retain prior asset locally.
- [ ] Video: recover latest promo/context, capture real updated app interactions including actual Instagram shielding if Instagram is available, assemble beat-timed footage/music/SFX, validate and render final MP4 with provenance.

## Visual direction
Warm ivory and charcoal surfaces with restrained parchment accents. Solid grouped settings rows; an open profile identity; a prominent solid dashboard summary; charts and app rules with subtle outlines. Reserve glass for floating navigation and small transient overlays. Permission access remains optional with explicit consent and truthful system-verified status.
