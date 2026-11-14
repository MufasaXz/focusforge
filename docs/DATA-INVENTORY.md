# FocusForge data-store inventory

Source inventory for the accompanying implementation, 2026-11-14. This is an inventory of application-controlled data and identified SDK stores; platform/provider internals are not an exhaustive physical-disk or subprocessors audit. The baseline resolved SDK/domain graph is in SDK-DOMAINS.md. No Supabase integration or Firebase Storage bucket was found in the previous read-only production audit.

## Remote records

| Service/store | Records and ownership | Export / deletion / retention |
|---|---|---|
| Firebase Authentication | UID, email, password verifier held by Google, provider identities, display/photo metadata and authentication timestamps | Account export selects public profile/provider metadata, never password hashes/tokens. Credential is deleted last through Firebase SDK after cleanup and fresh authentication. |
| Firestore `users/{uid}` | Own profile/level and legacy private children | Included in cloud JSON; server-acknowledged deletion after nested cleanup. |
| `users/{uid}/achievements` | Earned badge records | Private export and cleanup. |
| `users/{uid}/preferences` | Current limited `studyBackup` profile/progress and legacy settings | Export and cleanup; current cloud allowlist is `user`, `stats` without credited session IDs, and board opt-in. |
| `users/{uid}/sessionData` | Historical per-session rows; current saves delete legacy rows | Export and cleanup, even if obsolete. |
| Other known private subcollections | `stats`, `appStats`, `sessions`, `guardian`, `children`, `remoteRules`, `progress`, `catalog` | Included for legacy coverage; their presence in cleanup does not establish active child/guardian features. |
| `users/{uid}/deletionRefs` | Schema-2 inventory of nested/legacy private document paths | Export includes referenced owned documents; deletion removes targets and manifest. Export of unknown legacy records requires the existing schema-2 inventory; trusted auxiliary erasure recursively deletes every descendant under the own user path, even missing parents. |
| `leaderboard/{week}/entries/{id}` | Own shared name, ownerUid, study score | Collection-group owner filter in export and deletion; other accounts' rows preserved. |
| `studyGroups/{id}` and `/members/{uid}` | Group identity/settings, member list and own member status/progress | Own member rows exported/deleted. Deletion leaves groups, transfers ownership or deletes empty groups. Other members' information remains theirs. |
| `pairCodes/{id}` (legacy) | Historical childUid/claimedBy pairing references; no current pairing UI is inferred | Account-owned child/guardian query sections exported; trusted auxiliary erasure removes both fields’ matches. Legacy guardian reverse links are also cleaned. |
| `groupInvites/{code}` | Invite-to-group reference | Removed for deleted empty groups; retained for surviving groups. Do not remove another member's group. |
| `pipReports/{randomId}` (new) | ownerUid, redacted question/reply, reason, timestamp, expiresAt | Authenticated owner export; fenced transactional writes; paged account erasure; 90-day expiry and signed-scheduler sweep. Denied to client SDK by default rules. |
| Cloudflare `REPORTS` KV (legacy) | Time/random report keys, UID and feedback text | Worker `/data` pages the complete legacy namespace and returns/deletes only current UID's values. Existing 90-day TTL; KV propagation means erasure is not a globally atomic immediate operation. New reports no longer write KV. |
| `_aiLimits/{sha256(uid)}` | UTC day, answer/report counts, expiresAt | Limits export, erased before Auth, 2-day expiry/scheduled sweep. |
| `_resetLimits/{hash(address:email)}` | Email-associated reset abuse timestamps | Erased for current email on account cleanup. One-hour expiry/scheduled sweep. Network counters cannot safely be attributed/deleted for one person on a shared IP. |
| `_resetLimits/{hash(privacy:uid)}` | Temporary account-control request timestamps | Removed by final auxiliary erasure, otherwise one-hour expiry. |
| `_resetMailQueue/{randomId}` | AES-GCM encrypted email, retries, delivery lease and expiry | No raw address or reset URL/code stored. Completed jobs removed; 15-minute expiry. Historical pending mail cannot always be linked to UID; may briefly remain until delivery/expiry. Mail already sent cannot be recalled. |
| `accountDeletions/{uid}` | Immutable requestedAt stale-write fence | Included in limits export; retained at least seven days after request, swept only once Firebase confirms credential is absent. Paused deletions keep the fence. |
| `accountCleanup/schema` | Shared version-2 cleanup contract | Infrastructure metadata, not a user's record; retained. |
| Gemini / Groq | Redacted question/history, locale, numeric study totals for optional coaching | Not a FocusForge chat-history database. Provider processing, training settings, retention and request-erasure capabilities require contract verification. No unsupported zero-retention/no-training claim. |
| Vercel / Cloudflare / Firebase / Play Integrity | Request, authentication/integrity and platform security/access logs | Application logs avoid tokens/prompts, but provider logs/retention/backups need operator verification. App code cannot erase provider-owned historical logs by clearing preferences. |
| Gmail/SMTP and support mailbox | Reset email delivery, inbound complaints/support content | Provider/mailbox retention and legal-request workflow require manual action. Branded reset templates are preserved. |

## Local Flutter preferences

LocalStore uses the physical `ff.` prefix inside Android `FlutterSharedPreferences` (the plugin may add its own `flutter.` namespace). Values are JSON/text/booleans, **not an encrypted vault**. Detailed study history, raw app lists/rules and local coaching inputs are not uploaded to model context. `pip_cloud_consent` is a plain boolean choice, not a secret. Account-scoped snapshots must be filtered on export.

Every centrally declared key:

- `ff.ff.`
- `ff.user`
- `ff.stats`
- `ff.subjects`
- `ff.sessions`
- `ff.theme`
- `ff.theme.palette`
- `ff.theme.amoled`
- `ff.shield.whitelist`
- `ff.shield.youtube`
- `ff.shield.strict`
- `ff.shield.appListConsent`
- `ff.usage.categories`
- `ff.shield.breathEvents`
- `ff.notifications`
- `ff.achievements`
- `ff.achievements.accounts`
- `ff.achievements.historyOwner`
- `ff.achievements.linkedOwners`
- `ff.achievements.aliases`
- `ff.audio.volumes`
- `ff.audio.active`
- `ff.assistant.memory`
- `ff.assistant.aiDay`
- `ff.assistant.reports`
- `ff.goal.daily`
- `ff.goal.days`
- `ff.focus.presets`
- `ff.setup.startingPlan`
- `ff.setup.progress`
- `ff.focus.customPlan`
- `ff.focus.planLibrary`
- `ff.coachmarks.seen`
- `ff.focus.clock`
- `ff.leaderboard.optIn`

Dynamic namespaces and non-central literal keys (source locations are reproducible inventory, not secret values):

| Key/template | Call sites |
|---|---|
| `achievements.linked.$_uid` | `lib/core/providers/social_providers.dart:81` |
| `achievements.linked.$from` | `lib/app/bootstrap.dart:261` |
| `achievements.linked.$oldUid` | `lib/core/services/study_backup_service.dart:489` |
| `achievements.linked.$previousUid` | `lib/core/services/firebase_auth_service.dart:736` |
| `achievements.linked.$uid` | `lib/core/services/firebase_auth_service.dart:983` |
| `achievements.linked.${profile.uid}` | `lib/core/services/study_backup_service.dart:509`, `lib/core/services/study_backup_service.dart:633` |
| `achievements.unlockedAt` | `lib/core/services/local_store.dart:210` |
| `auth.deletedCredential` | `lib/app/bootstrap.dart:312`, `lib/app/bootstrap.dart:387`, `lib/core/services/firebase_auth_service.dart:224`, `lib/core/services/firebase_auth_service.dart:587`, `lib/core/services/firebase_auth_service.dart:606` |
| `community.blocks` | `lib/core/providers/community_providers.dart:10`, `lib/core/providers/community_providers.dart:21`, `lib/core/providers/community_providers.dart:23` |
| `leaderboard.consent.$uid` | `lib/core/providers/social_providers.dart:843`, `lib/core/providers/social_providers.dart:857`, `lib/core/services/study_backup_service.dart:764` |
| `leaderboard.consent.${profile.uid}` | `lib/core/providers/app_providers.dart:51` |
| `pip_cloud_consent` | `lib/features/assistant/assistant_memory.dart:177`, `lib/features/assistant/assistant_memory.dart:184` |
| `study.modified.$uid` | `lib/core/services/study_backup_service.dart:416`, `lib/core/services/study_backup_service.dart:766` |

Additional computed namespaces: `assistant.account.{uid}`, `study.account.{uid}`, `study.modified.{uid}`, `achievements.linked.{uid}`, `achievements.unlockedAt` (legacy map), `leaderboard.consent.{uid}`, and the account/alias maps held in StoreKeys. Runtime `LocalStore.exportAll()` enumerates every actual `ff.` key, so an unlisted new literal is not silently omitted; `DataExport.forAccount` excludes other accounts' caches/maps and the deleted-credential marker. Account deletion clears all `ff.` keys on this installation, including cached accounts; it does not delete other people's cloud accounts.

## Android and SDK stores

| Store | Contents | Control |
|---|---|---|
| `focusforge_shield`: `rules`, `app_blocking_paused` | App/package rules and local pause latch | Native JSON export; erase commits empty preferences and stops blocking service. |
| `pip_nudges`: `items` | Reminder IDs/times/titles/body | Native export; alarms/notifications cancelled and preferences erased. |
| `focusforge_live_activity`: `dismissed_target` | Timer-notification dismissal marker | Native export and erasure. |
| App cache directory | Temporary image-picker/media/plugin files | Native erasure deletes cache contents after study state reset. User-exported files and original gallery photos are outside app cleanup. |
| In-memory chat, timer, ShieldEvents queue | Current conversation/focus/interception state | Providers reset; native pending queue cleared. No ordinary chat persistence database found. |
| Firebase Auth / Google sign-in SDK preferences | SDK-managed session credentials and provider state | Not exported; SDK sign-out/deletion APIs used. No app-controlled plaintext password/API token storage was found. This does NOT prove SDK-managed tokens use Keystore encryption. A fabricated secure-storage dependency would not change SDK persistence. |
| Firestore cache | Startup disables disk persistence and clears older persistence; account deletion terminates/clears SDK cache | SDK-managed. Requires device verification for actual installed-upgrade paths. |
| OS UsageStats, permission grants, alarms, notification history | Android system records/permission state | App cancels own reminders and stops rules. Only Android/user can revoke special permissions and control system history; app deletion does not claim to erase all system records. |

## Boundaries still requiring operational verification

- Deploy website API before the new Worker and app. Retire old Worker writes before legacy KV cleanup; repeat legacy scans after propagation if migrating existing reports.
- Confirm all historical nested Firestore data is covered by schema-2 deletionRefs; the client SDK cannot enumerate arbitrary unknown subcollections for export; the new server eraser uses Admin recursive deletion.
- Cloud data control must fail visibly if either backend is not deployed, auth fails, or any page is unavailable. Do not delete Auth first.
- Scheduled retention is source code until deployed and monitored. Verify production indexes, cron, report sweeps and failure alerts. Set platform TTL policies as an independent safeguard if appropriate.
- Deleting every provider log, remote backup, delivered email or copy saved by another person is not something this code can promise. Publish justified retention and a support/rights process.
