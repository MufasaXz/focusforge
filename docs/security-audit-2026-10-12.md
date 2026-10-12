# FocusForge privacy/security audit — 12 October 2026

Scope: public repository history and current source, Android local-data handling,
account transitions, Firestore authorization and parent pairing. Changes are in
Android build 2018. This is a source audit with automated checks, not a claim of
complete penetration testing or verified production Firebase configuration.

## Findings and fixes

| Finding | Change |
| --- | --- |
| Real Firebase client configuration tracked in git; GitHub secret alert #1 | Removed operational google-services.json from current source, retained a placeholder example and ignored local credentials/config. |
| Android default backup policy could copy local history, settings, credentials and caches | Disabled backup and added explicit exclusions for cloud backups and device transfer. |
| Timer subject exposed on lock screens hiding sensitive content | Private notification with generic public countdown. |
| YouTube event could race an active-window package change | Verify active root package before inspecting YouTube view IDs. |
| Credentialless email linking marked an anonymous profile as linked | Require real email/Google credential UI; reject credentialless Firebase linking. |
| Account switch retained leaderboard opt-in | Reset consent before changing identity; retain device history deliberately. |
| Shared Firestore records persisted on disk and private family/group rows survived UI account changes | Clear prior disk persistence before sharing opens, disable persistence, gate services on remote credential backend, clear and scope private streams to account/current linkage. |
| Six-digit pairing lookup disclosed expired/claimed child identities to arbitrary authenticated accounts | New 16-symbol tokens with 80 bits of secure randomness. Revised rules deny stranger access to expired/claimed or legacy tokens; listings remain denied. |
| Parent could read the whole child profile; shared document schemas were unrestricted | Self-only root profile reads, parent reads limited to current summary/catalog/rules, bounded top-level shapes and board scores. Preserve legacy deletion/unlink. |
| Rules-tool development dependencies included a critical tar advisory | Updated Firebase CLI and test packages; critical finding removed. Remaining upstream dev advisories are documented below. |

## Repository secrets

Gitleaks 8.30.1 scanned 209 reachable local-history commits with all refs. It found
one Google API-key pattern, in historical android/app/google-services.json at
39a535a82cdcb766a9fbfdf9ed4f4ef71c5b6705, matching GitHub open alert #1.
No service-account private keys, signing credentials or personal access tokens
were detected by that scan. Scanner results cannot prove that every possible
secret format is absent.

The Firebase client API key is a public client identifier, extractable from an
APK; it is not a Firestore administrator password. Encoding it provides no access
control. Its exposure still merits project/API restrictions and abuse monitoring.
The maintainer must verify appropriate restrictions and rotate the key if needed.
No key rotation, restriction verification, alert closure or history rewrite was
performed. Historical commits, other branches and released APKs retain client
identifiers. Removing the current file is not revocation.

## Production boundary

A read-only unauthenticated Firestore REST probe for the users collection returned
403 PERMISSION_DENIED without returning user documents. This proves only that this
particular unauthenticated collection request was denied. It does not establish
that all production rules are safe. No real user records were opened, and no
production writes, rule deployment or administrator actions were performed.

Publish the complete revised firestore.rules yourself. New pairing requires
these rules and build 2018 on both phones. Existing guardian links can remain.
The local emulator tests validate checked-in rules, not deployed ones.

## Storage and erasure limits

Setup and detailed history belong to the device and survive sign-out/relogin.
They are not cloud backups and cannot be downloaded after an uninstall or onto
a new phone. Optional sharing publishes aggregates from this device. The privacy
screen now makes this explicit; clear analytics before handing a device to another
person. Account changes reset board consent but do not silently delete local work.

Account deletion first cleans authorized group/parent/current-summary records and
board weeks known to the local session log. Credential deletion and local reset
follow successful cleanup. Offline/timeouts may leave some queued deletions;
retry retains credentials/local history. Old unclaimed pairing tokens and board
weeks created on other devices need a privileged backend deletion job.

Parent PIN hashing remains a local commitment aid, not server authorization.
Firestore top-level app lists are bounded, but individual variable list items are
not deeply validated by these rules. A per-app document schema or backend validator
would enforce a stronger nested-data boundary. App Check and backend claim rate
limits remain deployment work for public scale.

## Development dependencies

Firebase CLI 15.33.0, firebase 13.0.0 and rules-unit-testing 6.0.0 are development
packages for local rule testing. Updated npm audit reports 16 upstream findings
(4 moderate, 12 high), zero critical; omit-dev audit reports zero. These Node
packages are not bundled into the Flutter APK. The suggested force fixes downgrade
major Firebase packages, so they were not applied blindly. Use only trusted local
rules projects and follow upstream fixes.

## Verification

The final test/build results and signed APK provenance are recorded in the release
notes and CHANGELOG.md. No successful physical-device or software-emulator runtime
QA was available. Native widget hosting, OEM live-bar promotion, Firebase provider
login and production deletion still need device/backend validation.
