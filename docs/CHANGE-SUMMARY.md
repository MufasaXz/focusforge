# FocusForge change summary

App, Android, Pip Worker and website changes are grouped into separate conventional commits, matching existing `fix(...)`, `feat(...)`, `test(...)` and `docs(...)` messages. All new commits use `mufasaxz <sudeepyadav7272@gmail.com>` without co-author trailers. The user-owned untracked `bug.md` and `ui-ux-review.md` are left out.

| Area | Main files | Result |
|---|---|---|
| Pip consent and coaching | `assistant_memory.dart`, `chat_screen.dart`, `chat_controller.dart`, `cloud_consent_dialog.dart`, `assistant_brain.dart`, `offline_coach.dart`, `privacy_screen.dart` | One-time neutral choice, persisted offline mode, withdrawal, local planning/recall/exam coaching and account-isolated preferences. |
| Privacy and transport | `ai_privacy.dart`, `ai_backend_service.dart`, `local_store.dart`, `data_export.dart` | Numeric-only context, known/common identifier redaction, HTTPS/no redirects, expiring owned feedback and no other-account export. |
| Cloud account control | `account_data_service.dart`, `firebase_auth_service.dart`, `auth_service.dart`, `bootstrap.dart`, `functions/cleanup.js`, `firestore.indexes.json` | Full known cloud JSON export, recursive/fenced erasure, Auth deleted last, legacy cleanup index and retry-safe failure messages. |
| Native cleanup | `native_privacy.dart`, `MainActivity.kt`, `ShieldEvents.kt` | Native settings export, reminder/rule/cache erasure and pending-event cleanup. |
| Worker security and reporting | `pip-ai-backend/src/{index,pip,privacy,auth}.js`, `wrangler.jsonc` | Strict max-300 schema, role/totals bounds, safety filters, quotas, secure errors/CORS, fenced report API and legacy KV export/erasure. |
| Release and scanning | `android/app/build.gradle.kts`, `proguard-rules.pro`, release manifest, `tool/build_secure_release.sh`, `tool/security_secret_scan.py` | Explicit release security flags, R8/Dart obfuscation, private symbols, verified fresh artifact and redacted history scan. |
| Website account controls | `api/account-data.ts`, `_legacyErasure.ts`, `_accountRetention.ts`, `_pipPrivacy.ts`, `ai-authorize.ts`, `reset-delivery.ts`, `src/accountData.ts`, `accountCleanup.ts`, `DeleteAccount.tsx`, `firebaseClient.ts` | Cloud JSON download, ownership enforcement, complete known erasure, report retention and App Check forwarding. |
| Website privacy/security | `src/accountErrors.ts`, `api/_security.ts`, `src/App.tsx`, `vercel.json` | Safe errors, correct public processing/children/retention disclosures, HSTS/CSP, existing branded reset templates preserved. |
| Legal and inventory | `docs/legal/*`, `DATA-INVENTORY.md`, `SDK-DOMAINS.md`, `SECURITY-HARDENING.md` | Comprehensive placeholder-marked drafts, 17-item status table, complete identified storage/SDK graph and manual/legal release work. |
| Tests | Flutter assistant/account/privacy tests; Worker tests; web account-data, cleanup, site/security and real Firestore emulator tests | Ownership, consent, offline behaviour, malformed input, erasure races, legacy cleanup, failures, small-screen accessibility and sanitized output covered. |

The privacy and terms drafts are copied into the website's `docs/legal/` too. Placeholders stay outside published page bodies. The website's factual disclosures are updated directly; statutory appointments, provider contracts, age eligibility and transfer safeguards remain explicitly unverified.

Validation is recorded in SECURITY-HARDENING.md and the external audit directory. The verified release bundle is `build/app/outputs/bundle/release/focusforge-1.0.1-3001.aab`; it is an ignored local artifact. Increase the Play version code before a new upload. Backend source must be deployed in the order given in the handover; a Git commit or local build does not deploy it.

## App implementation commits

- `0eeaad2 fix(security): redact Pip identifiers and lock down authenticated transport`
- `7ec3588 fix(security): validate Pip payloads and fence answer report storage`
- `53feaf5 feat(pip): add optional cloud consent and richer offline study coaching`
- `ea5f0ed feat(privacy): export cloud records and erase account data across services`
- `3fcc4d2 fix(android): harden release builds and keep private symbols outside the app`
- `1eacfca fix(privacy): distinguish cloud deletion from incomplete device cleanup`
- `3bb1624 test(privacy): keep another account’s Pip feedback out of data exports`
- `3fe752f fix(privacy): index legacy guardian links for account cleanup`

The documentation commit contains this summary, the legal drafts and audit inventories.

## Website commits

- `5d77c1a fix(security): sanitise public account errors and harden API responses`
- `bd6aaff feat(privacy): add web data export and complete cross-service account erasure`
- `cb43031 docs(privacy): align web disclosures and draft global privacy terms`
