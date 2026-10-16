# Shield reference comparison for build 2022

Inspection date: 2026-10-16. REA 6.4.0 with JADX headless 0.7.1, static APK analysis. The reference APKs were not executed; device/OEM reliability and battery impact cannot be ranked from decompiled code alone. No reference source or assets were copied into FocusForge.

## User-supplied APK identity

Both `/tmp/7c5965a7-b3fd-4242-8803-cc6935261994.apk` and `/tmp/c09de542-246e-4754-b536-eda471838986.apk` have SHA-256 `ea399d3c0ddf3a8957da467a3e1e220d488b80e0a67c9967c85b2eed9e7ec882` (49,924,187 bytes). Manifest identity is `ai.regainapp`, version `71.2.2046`, code 2046. Signature/provenance was not verified.

Evidence package: `ev_100464a0539b65557705c5ddebcacf3702d64f49cf0ee1945e9bcd8615f86105`. Complete JSON evidence is retained in the local delivery work folder `focusforge-work-files/stability-2022/rea-*.json`.

## Normal app blocking

`MyMonitorService.onStartCommand` starts a single monitoring coroutine and returns START_STICKY; `j` avoids starting another active job. Evidence: `ev_d589f1cde218b329a779e762c9d61aa9842c20320a0bf9fa51d1b86641b8490f`, `ev_42ff5626c3e88c10199b6a9338ee64aa1dd04f30b5dd852f5df31d795417d7fd`.

`MyMonitorService.a` consumes foreground usage events, ignores pause events for new block decisions, and routes focus-session/app-limit decisions to overlays. Java reconstruction failed for this coroutine, so the observation is bounded to REA's complete smali fallback. Evidence: `ev_606f3fc100892d9f4d198fef0fc3a6366cd8e0b048b07238b83979713e2db5f4`.

`zf.a.a` caches recent usage events, expands history queries from 60 seconds through 24 hours, and has an earlier-unmatched-resume fallback for quick switches. Evidence: `ev_9e43113c78467f10cfc46cb6612d2eace3a4194c8f453bb2c89f67c3f610cad5`. Decompiled loops have reconstruction ambiguity; this is not proof every branch works at runtime.

FocusForge already uses one UsageEvents foreground service for whole-app limits, with replay on unlock and a bounded overlapping query. Its regression test exposed a real gap: Recents can resume without pausing the underlying app, then close without another app resume. ForegroundAppTracker now retains a bounded set of unpaused activities and restores the latest eligible one. Matching pauses and screen boundaries remove candidates; timestamp fences reject replayed events. Tests cover actual underlying pauses, another task, delayed publication, activity handoff and replay. This implements the useful quick-switch principle independently and retains FocusForge's activity-specific handling.

## Shorts blocking

`MyMonitorInAppBlockService.checkForBlockContent` classifies YouTube content before applying the configured short-form overlay, and resets short-form tracking on other content. Java failed; complete smali fallback retained. Evidence: `ev_1a536692c8cb6a60fb76e54f86e0619c4d19925748b6c0e9d4a65749dddc17c6`.

`getYoutubeChannelNameAndContentType` groups screen nodes by layout/orientation, checks home/watch content, then seeks short-form controls and rejects candidate groups positioned in the left part of the layout. This illustrates the importance of context and avoiding carousel/ordinary-video false positives. Evidence: `ev_b5ab24ed409970974d8ea1c0df634eb29d55f0dc8d2ca3689ec7b51206ea5125`. This method has a JADX duplicated-block warning; channel-name/layout heuristics were not transplanted because their language/device coverage is unverified. The inspected accessibility callback itself only checks its non-null argument; it does not establish the service's polling cadence. Evidence: `ev_bf47b3e43ceb4578f944300cc75a7d6a3831878c46787e46aa0ef532eeacc660`.

FocusForge now classifies only visible, exact YouTube resource identities. Hidden player nodes, thumbnail IDs containing a player substring, and other-package IDs cannot identify an active Shorts player. Shorts shelves remain distinct from playback; a miniplayer container does not bypass the feed rule. These checks have pure native regression coverage.

An additional official reference, Shorts Blocker 1.0.11 (`dev.atick.shorts`, SHA-256 `6eb539d5b9997ed3090eca9fd3f4ce9a5d1811aa1ece26922e05e3185ce475c9`), observes window changes and subtree content changes, uses a bounded traversal and identifies `reel_progress_bar`. Evidence: `ev_a324fe47260db08bdcaf59d903e0af7ff854941b8b310220573aecf1323fea69`. FocusForge independently added subtree event handling and that exact player identity, with event-policy tests. Its bounded off-main-thread traversal, package guard, loading retry and overlay controls are retained.

## Verification boundary

Native policy tests establish deterministic lifecycle, resource-signal and event-filter behavior. They cannot establish recognition on every current YouTube screen or every manufacturer's Android build. Normal app limits and Shorts filters still depend on the user-enabled Android permissions and OS service lifecycle. No claim is made that static reference inspection proves Regain is globally better or worse.
