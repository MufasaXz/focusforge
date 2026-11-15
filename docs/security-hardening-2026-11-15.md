# FocusForge targeted hardening — 15 November 2026

This source review accompanies the profile, timer and offline Pip improvements.
It is not a penetration-test certificate or a guarantee that the app has no
vulnerabilities. No production accounts or third-party systems were attacked.

## Findings fixed

| Area | Finding | Change and regression coverage |
| --- | --- | --- |
| Local photo import | A compressed-size limit alone allowed images with excessive decoded dimensions. | `lib/core/services/profile_photo.dart` checks dimensions before decoding pixels: maximum 8,192 per side and 16 million pixels, with only the first frame decoded. Existing thumbnail re-encoding and metadata stripping remain. `test/profile_photo_test.dart` covers oversized JPEG dimensions. |
| Worker authentication | Failed signing-key fetches could be repeated by sequential requests throughout an upstream outage. | `pip-ai-backend/src/auth.js` caches failures for 60 seconds and fails closed. Concurrent fetches still share one request. Tests cover repeated failures, cooldown recovery, malformed signatures and missing required authentication claims. This is per Worker isolate, not a global rate limit. |
| AI provider responses | Provider JSON was parsed without a response-byte ceiling. | `pip-ai-backend/src/index.js` caps streamed upstream bodies at 256 KiB before JSON parsing. The Worker tests cover oversized responses and generic failure handling. |
| Offline command interpretation | Negated, hypothetical or explanatory requests could be interpreted as app actions. | The offline language/parser layer guards recognized timer and reminder actions. Tests cover English, Hindi and Hinglish refusals and how-to questions, while existing explicit-command tests preserve normal actions. This is a bounded rule-based parser, not universal language understanding. |

## Credential scan

Ran `tool/security_secret_scan.py` against the app and website working trees,
Git history and reflogs. It examined 4,155 app Git blobs and 359 website Git
blobs before the new commits: no credential candidates requiring review and
no historical keystore/private-key file paths were reported. Firebase public
client configuration is classified separately. Reports contain locations and
fingerprints rather than credential values.

Pattern scanning cannot detect every secret format, deleted remote copies,
external logs or private services. Ignored local signing/configuration files
are inventoried by metadata, not published. No credentials were rotated on
the basis of this result.

## Existing safeguards reviewed

- Android's main manifest disables cleartext traffic and backup. Release
  Gradle configuration enables R8 and resource shrinking.
- Firestore rules scope private records to the owning account and restrict
  writes by collection. No rule changes were required for portrait IDs;
  the existing bounded avatar string field carries them.
- The Worker already bounds input, verifies Firebase identity, calls the
  authorization service for account state/quota checks, restricts browser
  origins, and returns generic errors. CORS is not the authentication boundary.
- Level-based avatars are cosmetic local rewards, not an authorization or
  payment boundary. Selection is checked in the notifier as well as the UI.

## Validation and rollout

Regression coverage includes the offline assistant corpus, profile and avatar
widgets, photo validation, timer interactions and Worker request tests.
Final checks: 1,171 Flutter tests passed, 48 Worker tests passed, and
`flutter analyze --no-pub` reported no issues.
Reproducible screenshots in `tool/capture_lowdpi_test.dart` and
`tool/capture_avatars_test.dart` check the revised phone layout and portraits;
the phone capture asserts Full screen stays clear of the floating controls.

App changes need a future Android release. Worker source changes require a
separate deployment; a Git push alone does not deploy this Worker. This task
does not change versions, build an APK, deploy the Worker, or modify the website.
