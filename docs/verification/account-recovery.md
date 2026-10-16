# Account recovery and profile refinement

Returning linked accounts now retry transient cloud reads twice, refresh a rejected credential once, and share one in-flight restore between the Firebase SDK event and the explicit sign-in result. Recovery errors retain their diagnostic type/code without logging account IDs, credentials or saved content. The UI no longer describes every backup failure as an internet outage. A single app-level loading card follows actual restore/retry state. Startup renders the local shell before cloud recovery finishes. Cloud writes remain fenced until the server read succeeds.

Recovery work is bound to a credential generation. Sign-out clears its cached request and detaches the next session's queue, so a quick same-account sign-in can finish before a stale read returns. Stale responses cannot reopen account gates or clear the new session's loading state.

The precise exception on the reporting user's phone is still unobserved: no device is attached. Read-only live rules inspection confirmed the deployed rules matched the previously shipped rules. A disposable anonymous credential successfully read its absent settings document (404 NOT_FOUND) and ordered empty session query (200), then was deleted (200). This establishes that those owner reads are allowed; it does not reproduce that user's linked-account network environment.

Profile photos use the system gallery picker and become a 128-pixel JPEG thumbnail with metadata discarded, bounded to 24,000 base64 characters. The thumbnail travels in the private settings backup and in the optional public leaderboard row. Name and photo changes republish the current weekly row and restore across logout/login. Guests keep their photo locally until linking. Photo removal updates the private backup and replaces the public row without the photo. Private backups retain the existing whole-settings timestamp conflict policy.

Subject breakdown uses full-width rows, per-subject times, percentages and bars alongside the selectable ring. The current leaderboard row has a gold outline on the normal surface. YouTube has a single heading and concise switches, without the manual channel editor, repeated status box, explanatory card or whole-app shortcut.

## Educational creator evidence and limits

REA inspected the supplied APK statically, reusing the previously verified SHA256 ea399d3c0ddf3a8957da467a3e1e220d488b80e0a67c9967c85b2eed9e7ec882. The current follow-up evidence is stored outside the repository under focusforge-work-files/account-recovery-2026-10-16.

- ev_d756ffd0e122f4967b4bb111ca149f5388bb5b715b1a944c5adae2d59339711b: creator/handle branch chooses metadata lookup.
- ev_e763a55f7d5dd8c436e2fbfecec3ae952cca89409798715a9b95e449f4bf9ee3 and ev_b516f6ca818dc5966412ca0681e29d52fd10478d629b7095262a38833731a50b: cached productive metadata, absent/stale lookup, daily refresh logic. Java reconstruction warnings apply; name path includes complete smali fallback.
- ev_276b5ac84b8e27a858fcb338440e796da08784e9a808928d8a69461fb0db1249 and ev_a432663f3a710097daaa2068430f6750d46d0d493fad1538e1656e8068c4d463: remote Retrofit response supplies channel categorization by ID, name or handle. No classification algorithm is supplied by this app code. The earlier evidence establishes a three-second bounded lookup with whitelist fallback.

FocusForge independently recognizes an exact bundled catalog of educational creator names/handles, plus previously saved creator choices. It makes no remote creator requests and does not read video titles or search queries. This enables recognized channels without manual setup, but does not classify arbitrary educational videos. Missing/unknown creator labels are paused while study-only filtering is enabled. Display-name matching cannot prove channel authenticity and mixed-content channels remain channel-level decisions. YouTube layout changes/fullscreen creator visibility and real-device behavior remain unverified.

## Validation

- 461 Flutter tests pass, including bounded retries, one restore for duplicate SDK/explicit events, fresh same-account recovery before a canceled read returns, modal behavior, name/photo update and logout/login restore, photo preservation on colour changes, compact leaderboard geometry and simplified Shield controls.
- 70 Android tests pass, including one new educational-creator recognition regression and three pre-existing local tests excluded from commits.
- 25 Firestore rules tests pass; photo rules bound public payloads and enforce ownership. Existing cleanup still removes leaderboard documents and private preference backups, so photos introduce no separate deletion store.
- Offline localization generator validates all 25 languages. New translations are machine-assisted and require native-speaker review.
- Analyzer reports no issues and `git diff --check` passes. Independent review identified three issues (same-account recovery reuse, photo removal on colour changes, and incomplete creator-text disclosure); all were resolved and rechecked. Recovery and colour regressions were reproduced before their fixes.
- Updated Firestore photo rules were deployed to `focusforge-1edf7` and read back byte-for-byte against the local rules. No other deployment or build upload was performed.

Before store release: test Google/email returning-account recovery and the system photo picker on an actual phone; verify supported YouTube creator layouts; update website privacy/FAQ to describe profile thumbnails and local catalog comparison. No universal educational-detection guarantee or fixed network recovery time is claimed.
