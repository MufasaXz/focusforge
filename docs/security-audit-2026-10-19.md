# FocusForge security review — 19 October 2026

Reviewed app branch `1.0.4`, starting at `fd67c47` (`1.0.4+2027`). This report supersedes the older audit's storage description: linked accounts now have private study backups.

The review found and fixed account-boundary privacy bugs and a bounded local Shield integrity issue. No unauthorized cross-user Firestore access or automatic upload of detailed app-usage/Shield records was found in the reviewed paths and tests. This is source, dependency and emulator evidence, not proof that every possible leak or vulnerability is absent.

## Fixed findings

| Finding | Impact and conditions | Fix |
| --- | --- | --- |
| Previous account name reused when building a different account's profile (medium) | On a shared installation, Firebase profile construction reused the stored display name. When the new account had no profile/settings backup, that name could be saved into its private backup and later shared through its social features. Older signed-out profiles with no link marker could also become eligible for transfer after choosing Skip. | Accept the device profile only for the same UID or an anonymous guest with an explicit false link marker. Both Firebase and local fallback auth initialize that guest marker only for a fresh identity; unknown existing markers remain unknown after Skip. Regression cases cover linked, signed-out, missing-marker upgrade and session-only-backup states, verify the uploaded profile and preserve confirmed guest promotion. |
| Group totals included sessions owned by other accounts (medium, conditional) | If retained/mixed local history contains another owner's sessions, the group summary included that owner's minutes. Normal account restoration already replaces active session history; this fixes the sharing calculation's missing defense as well. | Apply the existing owner/guest-alias/history-owner predicate before including a session in group totals. A regression distinguishes own, linked guest, legacy own and foreign sessions. |
| Excessive temporary Shield access from launch data (low) | An app able to launch the exported launcher activity could supply a large grace duration. After the user completed the breathing gate and chose to continue, the Accessibility engine accepted that duration. This was a local commitment-feature bypass, not silent account access or data exfiltration. | Bound Dart launch and channel values and the native Accessibility sink to 5–600 seconds, matching the existing whole-app engine. Normal user confirmation remains required. |
| Vulnerable transitive packages in Firebase test tooling | The Node-based rules harness contained old gRPC TLS/error-context code, an FTP directory parser vulnerable to CPU exhaustion, and an old UUID buffer API. These packages are development tooling, not Flutter APK code. | Override `@grpc/grpc-js` to `^1.14.6`, `basic-ftp` to `^6.2.3`, and gaxios's `uuid` to `^11.1.1`; update the lockfile and run the Firestore regressions. |

## Data paths and controls checked

- Authentication: Firebase email verification, Google credential flow, guest-only fallback, restoration/generation fences, reauthentication and deletion ordering. The app does not store typed passwords or OAuth tokens in its `ff.` preferences. Firebase/Google SDKs manage their own session state.
- Private cloud data: profile, subjects, plans, goals, totals, completed study sessions, earned badge IDs/dates and normalized profile thumbnail. Firestore rules restrict account paths to the owner; credential verification and deletion markers gate writes.
- Optional social data: authenticated leaderboard readers can see opted-in display name, account ID, photo, level and weekly minutes. Group members can see names, weekly totals and active focus status. Invite lookup uses an exact 10-character cryptographically generated code, with listing denied.
- Detailed device activity: installed-app queries, usage totals, Shield rules/events and YouTube creator-node comparisons remain local in the reviewed code. Accessibility is configured for YouTube; screen text is not sent through a network client.
- Native boundaries: app-owned services/receivers are unexported; Accessibility requires the platform bind permission. PendingIntents are explicit and immutable. Launcher extras select UI paths and cannot directly grant access. Library-added Firebase OAuth activities remain exported for their documented flow; Play Services revocation and profile-install receivers require permissions.
- Release merged manifest: `allowBackup=false`, explicit cloud/device-transfer exclusions, `usesCleartextTraffic=false`, no `debuggable=true`. Firestore persistence is disabled and old disk persistence is cleared before services attach.
- Avatar input/output: picker requests a small image without full metadata; encoding copies pixels to a 128px JPEG, dropping original metadata. Remote thumbnails are length/dimension checked and do not fetch arbitrary image URLs.
- Notification and external I/O: timer notifications provide a generic public version and mark details private/local-only. Browser/mail actions use fixed HTTPS resources or an explicit user-initiated report. Ambient audio uses bundled assets. No custom certificate bypass, shell-execution path, WebView script bridge or arbitrary outbound HTTP client was found in app code.

## Deployed-rule verification

Read only the Firebase Rules management API; no production user records were read or modified. The deployed `cloud.firestore` release, last updated `2026-10-16T06:38:12.874933Z`, points to ruleset `8bf142b7-a44f-4ff5-bfd1-b53661904b00`. Its source exactly matches the tested local `firestore.rules`:

```text
SHA-256 7a89c9fe1cbde614e68f0a1cdad7ba9ac9d8a7335a5f7b82368fbd9fb6810588
```

The emulator regressions include unauthorized reads/deletes of private and social data, unauthenticated access, forged group joins/member injection, invite overwrite, peer removal, recursive cleanup grants, unverified email accounts and deletion fencing. No Firestore-rule production deployment is needed for these client changes.

## Dependency and secret checks

- OSV batch query: 130 hosted Pub packages from `pubspec.lock` and 150 Maven coordinate/version pairs parsed from the resolved release dependency report; no known advisory matches returned on the review date. This includes dev/test Dart packages and some repeated constrained/resolved Maven coordinates; database coverage is not a code audit.
- Functions `npm audit --omit=dev`: zero reported vulnerabilities.
- Rules tooling audit reduced from 16 flagged package nodes to 5: `firebase-tools`, `chokidar` and `braces` inherit the unresolved braces advisory `GHSA-vfj7-8cjw-p6xm`; `@google-cloud/pubsub` and `@opentelemetry/core` inherit `GHSA-8988-4f7v-96qf`. No fixed compatible braces release was available. Forcing a major telemetry/PubSub API change merely to suppress the scanner is deferred. These dependencies stay local to the development harness and are absent from the APK. Use trusted project/watch patterns and keep the harness isolated from untrusted traffic.
- Gitleaks 8.30.1 scanned 292 reachable commits (~13 MB). One historical match: a Firebase client API identifier in `android/app/google-services.json`, introduced at `39a535a82cdcb766a9fbfdf9ed4f4ef71c5b6705`. It is already removed from the current tracked tree. Such identifiers are extractable from an APK and are not database passwords; authorization relies on Firebase credentials/rules. No private signing key, service-account credential or bearer token was reported by this scan. No values are included here.
- Current Dart source scan reported no secrets. Local signing material, auth caches and ignored machine-specific secrets were not copied into reports or commits.

## Verification

- Flutter 3.47.6 / Dart 3.13.5: full suite **488 tests passed** after the final account-marker fixes; `flutter analyze` reports no issues.
- JDK 21 / Gradle: native debug unit tests (65 tests, zero failures) and release merged-manifest processing pass. SDK/third-party deprecation warnings remain.
- Firestore emulator: 30 rule tests pass, including five added abuse-regression groups.
- Functions emulator: all three cleanup/identity/migration tests pass. Running the Functions suite without the emulator fails because the migration test requires a demo Firestore endpoint; use `npm run test:emulator`.
- Security regressions were run against the previous behavior first: cross-account name, Skip/fallback marker and excessive grace tests failed; group ownership test included 595 minutes instead of the intended 40. The corresponding fixes make those cases pass.
- Independent code review found the missing-marker upgrade path, which was fixed and re-reviewed. The final marker follow-up independently passed 39 targeted tests plus three outside-tree probes covering fresh guests and fallback restoration. No remaining actionable finding was reported within the reviewed change scope.

Reproduce the main checks from the repository root with the installed Flutter SDK on PATH:

```sh
flutter test --reporter expanded
flutter analyze
git diff --check
```

With JDK 21's `bin` on PATH, run `./gradlew :app:testDebugUnitTest :app:processReleaseMainManifest --console=plain` from `android/`, `npm test` from `tool/firebase/`, and `npm run test:emulator` from `functions/`. The test harnesses use demo Firebase projects; no production-user fixture is required.

## Remaining assurance limits and intentional local behavior

1. Device preferences are app-private plaintext, not application-level encrypted storage. Detailed history intentionally survives sign-out, as disclosed in the app. This protects against ordinary sandboxed apps, not an unlocked shared phone, rooted device or compromised OS. `Export all data` deliberately previews/copies every local `ff.` key, including cached account backups; it is a device-wide export, not a current-account-only export. Clipboard consumers and user-granted notification/accessibility access are separate OS trust choices.
2. Private Firebase backups are access-controlled and transported by Firebase SDKs; they are not end-to-end encrypted against project administrators. No App Check integration is present in this source. Quotas, abuse/rate limits, API-key restrictions, IAM, authentication enumeration/password policy and deployed Functions/App Check configuration were not changed or fully audited.
3. Existing unrelated local Gradle edits disable release lint/lintVital checks. They were preserved and excluded from the security commit. Passing native tests/manifests is not a claim that Android lint passed.
4. No physical Android device or emulator was attached. Runtime traffic interception, OEM backup/lock-screen behavior, Accessibility behavior on current YouTube layouts, rooted-device extraction and penetration testing were not performed. No new signed APK or Play Store release is produced by this source-fix commit.
5. Old wrongly attributed profile data already saved in another account cannot be safely distinguished from a legitimate user-entered name and was not deleted. Updating the app prevents the reviewed carryover paths going forward.
