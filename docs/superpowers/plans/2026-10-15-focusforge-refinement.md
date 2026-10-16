# FocusForge refinement implementation plan

**Goal:** Restore the earlier navigation, simplify setup without glow, let users remove subjects safely, and improve leaderboard hierarchy.

**Architecture:** Keep the existing Flutter/Riverpod flows and persisted models. Limit setup styling changes to onboarding; preserve Home and timer action glow. Subject removal retains completed sessions and daily total goals.

**Tech stack:** Flutter, Riverpod, SharedPreferences, existing Firebase leaderboard.

**Spec:** User request in this session, 2026-10-15.

## Constraints

- Restore the phone navbar from commit 00b2d3f. Keep tablet navigation and semantics.
- Do not modify pre-existing Android test edits or untracked handoff/capture files.
- Keep account consent, optional usage access, real leaderboard levels, report/hide controls, large-text support and draft restoration.
- Use official reference APKs and actual REA findings; distinguish static evidence from runtime observation.
- Release 1.0.4+2032, existing signing key, author and committer mufasaxz.

## Tasks

- [x] Research official Loop/Medito APKs with REA, save evidence and design adaptations.
- [x] Restore navbar in lib/app/shell/app_shell.dart and StadiumBorder layout expectation.
- [x] Simplify active onboarding copy/layout. Remove setup card/splash shadows; use flat selection, smaller headings, compact plan preview and concise completion summary. Preserve auth/error/permission disclosure.
- [x] Add visible Manage subjects sheet to Focus. Confirm each removal, persist catalogue, clear selected timer tag, preserve completed sessions. If a removed subject has daily allocations, clear allocations while retaining the total target so the exact allocation invariant remains valid. Test cancel, selected/unselected removal, history, storage and goal preservation.
- [x] Redesign leaderboard with weekly title/date range, compact personal summary, clear leading ranks and own row. Preserve opt-in and genuine empty/error/loading states. Verify light/dark and 320dp at 2x text.
- [x] Run focused and full Flutter tests/analyzer; inspect captured screens, review final diff; build signed APK and verify version/certificate/install.
- [ ] Commit/push, upload APK to Gofile, record public link and verification in release notes/memory.

## Verification commands

```sh
/home/aosp/projects/flutter/bin/flutter test --no-pub test/focus_subject_test.dart test/onboarding_subjects_test.dart test/leaderboard_test.dart test/tablet_layout_test.dart
/home/aosp/projects/flutter/bin/flutter test --no-pub
/home/aosp/projects/flutter/bin/flutter analyze --no-pub
```

## Decisions

Work in the existing 1.0.4 checkout; no worktree needed for this bounded follow-up. Subject removal means removing the active catalogue entry, not deleting earned focus time. Removing an allocated subject resets the optional split, preserving the daily target.

## Verification evidence

390 Flutter tests passed, analyzer clean, independent concurrency repros fixed and retained in test suite. Release build2032 succeeded; APK signature/version verified. Light/dark capture harness passed. Screenshots retained; image-display tool returned no visible render, so no manual visual-review claim. REA reference findings are in the companion research document. Gofile upload size/MD5 matched, public page HTTP200. Android11 emulator installation returned Success; Home, Focus and subject-management UI trees verified on the installed2032 APK.
