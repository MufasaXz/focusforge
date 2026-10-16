# FocusForge follow-up implementation plan

**Goal:** Finish the four changes recovered from Claude's October 15 session and deliver a signed APK.

**Architecture:** Keep subjects in the existing persisted provider, with no automatic seed catalogue. Extend weekly leaderboard rows with an optional level for legacy reads and a required actual stats level for new writes. Keep Material navigation and its semantics while refining its surface and selection styling.

**Constraints:** Work on branch 1.0.4. Preserve unrelated native-test and untracked files. New commit messages must not contain the user's prohibited marketing term. Author and committer: mufasaxz <sudeepyadav7272@gmail.com>. Publish only to the existing repository and authorized Gofile delivery.

- [x] Subjects: add regression tests for an empty first run, onboarding selections, persistence, and adding subjects later. Change SubjectsNotifier._base to an empty list. Preserve authoritative saved lists, including empty lists. Update tests that assumed seed fixtures to seed their own data.
- [x] Home: update the allocated-goal regression to require the daily gauge and subject breakdown without the duplicate allocation tile. Remove _SubjectAllocationCard and its call site.
- [x] Leaderboard: test old/new row parsing, invalid levels, actual-level publication and opt-out. Extend BoardRow, LeaderboardEntry, service publication and provider mapping. Publish on stats changes. Allow optional positive integer levels in Firestore rules, preserving old writers; exercise valid/invalid/foreign-owner rule paths. Refine ranked rows with initials, visible levels, readable durations and accessible overflow behavior. Update sharing copy.
- [x] Navigation: retain four destinations, reselect behavior, coach anchors and tablet rail. Refine the floating surface, border, selected indicator, labels and icon sizes; verify 320dp, large text and tablet regressions.
- [ ] Verification and delivery: run focused tests, Flutter analyze, the full test suite and Firestore emulator checks. Review light/dark captures. Build signed 1.0.4 APK with a new build number above 2029; inspect version and signing certificate. Deploy tested backward-compatible rules if credentials permit. Commit selected files, push branch 1.0.4, upload APK, validate returned size/checksum and record public delivery notes.
