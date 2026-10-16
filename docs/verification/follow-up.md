# Account, timer, language and Shield follow-up

Work is restricted to the development branch. No build is uploaded and no merge to main is part of this change.

## Account restoration

A returning account with no local settings revision uses the saved account settings instead of treating guest defaults as a new revision. Equal revisions also prefer the server. Session history still merges by session identity. Integration coverage signs in, hydrates saved subjects/plans/goals and consent, republishes weekly minutes and recognizes the account's leaderboard row. Settings still use a whole-settings timestamp conflict policy; this is not a field-by-field multi-device merge. Unsynced changes must finish uploading before an uninstall.

## Home and open issues

The Home shortcut puts subject and focus/break details on the left and a gold Start focus pill on the right, with measured fallback stacking for narrow widths or large translated text. The original screenshot is not stored with this change, so geometric regression tests are the retained evidence.

Issue #1 is addressed by Turkish localization and an optional bounded random focus plan. A focus duration is sampled once per block, retained across pause/background/restart and hidden while random focus runs. Breaks keep their normal countdown. The actual completed duration is credited. Issue #2 is addressed by keeping onboarding's input subtree stable when the keyboard changes available height.

Timer completion snapshots keep a pending session journal until durable session storage succeeds. Stable segment IDs prevent duplicate recovery after millisecond timestamp serialization. Generation and account checks stop queued recovery from crediting a different account. Session minutes and gamification totals are still separate storage writes: an interrupted stats write can leave XP behind a durable session. This change does not claim transactional XP recovery.

## Study channel filtering

REA static inspection of the supplied artifact identified channel allowlisting and a bounded metadata classification path. The classification source and its accuracy could not be established; runtime behavior was not observed. The implementation is independent and uses a local list of user-selected creator names or @handles, compared with visible creator nodes inside supported current-video owner regions. It does not send screen contents to a server, copy reference source or classify every video as educational.

Shorts filtering retains priority and an explicit whole-app boundary takes precedence. The async screen check rechecks the latest rules before deciding. Names/handles are only read for the opted-in study-channel feature, are not retained in activity history and are not uploaded. Other apps' screen text, titles and typed search terms are excluded.

Real-device verification remains required for supported YouTube layouts, hidden creators in full-screen mode, local-language layouts and device battery restrictions. A page without a recognized allowed creator may be paused. Selected channels can still publish noneducational material; the UI describes this as a selected-creator filter.

Before releasing this feature, update the website's privacy Access section, permission FAQ and support copy to include optional study-channel filtering. Required wording: when enabled, visible creator names or handles on supported video pages are compared locally with the user's selected channel list; labels are not retained or uploaded, and this does not classify every video. The in-app disclosure and Android accessibility description already include this behavior. No website deployment is authorized in this follow-up.

## Verification

- Full Flutter suite: 447 tests passed. Includes returning credential restore, leaderboard row ownership, timer restart/retry boundaries, random focus, keyboard focus, narrow Home rows and RTL.
- Flutter analysis of lib and test: no issues.
- Android debug unit suite: 69 tests passed in 13 suites, including 5 study-channel policy tests. Three pre-existing local foreground-tracker tests are preserved outside these commits; the committed suite contains 66 tests. Android resource processing and Kotlin compilation passed.
- Offline generator check: 1,169 source keys in every translated catalog, valid placeholders and matching generated files. Direct literal localization audit found no missing source lookup keys.
- No backend schema or rules changed. No production account deletion or new build upload was performed.

Third-party Gradle deprecations remain in the build output; there are no Flutter analyzer warnings. No emulator or real YouTube playback validation is claimed for this follow-up.
