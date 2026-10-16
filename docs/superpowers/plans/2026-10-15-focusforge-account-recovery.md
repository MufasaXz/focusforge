# FocusForge account recovery and release 2022

**Goal:** deliver version 1.0.0+2022 as signed APK and AAB with reliable returning-account recovery, persistent opt-in leaderboard presence, consolidated subjects, refined timer controls and evidence-based Shield improvements.

**Architecture:** private owner-only study backup restores account profile, subject catalogue, plan library, goals and completed session records. Guest Skip uses a local identity immediately. Authentication events are serialized and stale events rejected. Explicit leaderboard opt-out withdraws a row; sign-out only closes authenticated access.

## Constraints
- Preserve the existing AppBlockingPolicyTest.kt edit and unrelated untracked files.
- Account isolation, email verification, deletion fence and history deduplication remain enforced. Usage/app-access records stay local; only study records requested by the user gain private backup.
- Restore completed setup before navigation. Weekly progress is calendar-aligned, absent study days are zero, and a week with no study hides the initial weekly panel. Retain saved goal target as an editable preference after an expired week.
- Reference APK findings require actual REA evidence; implement normal UI/lifecycle patterns independently unless an upstream license permits reuse.

## Tasks
- [x] Reproduce auth/recovery failures with regression tests; implement private backup, account restore and immediate guest Skip.
- [x] Add owner-only Firestore backup rules and deletion coverage; update privacy copy and emulator rule tests.
- [x] Consolidate subjects, infer appearance, restore Home timer placement and dim Focus action glow.
- [x] Persist consent per account; republish after login, retain rows on sign-out, serialize opt-out; refine leaderboard UI.
- [x] Inspect official blocker APK with REA; simplify overlay/icon and implement supported app/Shorts fixes with native tests.
- [x] Run Flutter/analyzer/native/rules checks and independent review where workers available; capture runtime evidence.
- [x] Build/verify/upload signed APK and AAB 1.0.0+2022; commit/push and update delivery notes.

## Execution note
Parallel workers failed twice before making changes because their model service reported no available accounts. Work proceeds sequentially in the primary session; the saved briefs remain the scope checklist.

## Completion evidence

Release behavior, checks, download links and remaining limits are recorded in docs/releases/1.0.0-build-2022.md. The Home session_shortcut.dart file matches the historical desired layout and has no final diff. Final Android install/launch QA could not complete because the software emulator lost system/package services; deterministic native policy checks passed. Existing AppBlockingPolicyTest.kt edits and unrelated handoff/capture files remain outside the release commit.

Earlier independent reviews identified failed-read overwrite, retry exhaustion, offline sign-out, timer identity, consent rollback, known offline launch, canceled restore and stale native filter races. Their concrete findings were fixed and regression-tested, including cancellation during an awaited local restore write. The additional final reviewer has not yet produced a readable report; do not treat encoded messages as review approval.
