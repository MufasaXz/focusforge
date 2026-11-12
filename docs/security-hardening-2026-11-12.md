# Security fixes — 12 November 2026

The app and its Worker now use a server-enforced daily AI allowance. The Worker
calls the website's `/api/ai-authorize` before an answer or report. That endpoint
verifies Firebase ID tokens **with revocation checking**, rejects disabled or
deleted users and unverified email/guest accounts, checks the account-deletion
fence, and atomically claims a quota in Firestore. Answers are limited to five
attempts per UID per UTC day across installations and Cloudflare locations.
Reports have a separate 20-per-day allowance. Failed provider calls still consume
an attempt; no refund race can be used to evade the cap. Local counters are UI
hints, not security controls.

The authorization service fails closed on network, Auth, or Firestore failure.
The Worker forwards only the token, optional App Check token, and operation;
question text and provider keys never go to the website. It also retains its
short-term per-IP, per-user, and shared limits. `_aiLimits` and `_resetLimits`
are server-only collections with no client rule grants. Their bounded expiry
sweeps use document-version preconditions to preserve concurrent updates.

Password recovery now uses Firebase's own privacy-protected email delivery via
the website. No custom Admin account lookup or SMTP sender remains in the active
reset path. Emails use Firebase's configured template/handler; the previous
custom Gmail branding is no longer used. The website needs its existing
`VITE_FIREBASE_API_KEY` or a separate `FIREBASE_WEB_API_KEY` at runtime, as well as
`FIREBASE_SERVICE_ACCOUNT` for counters and AI authorization. Keep Firebase's
improved email privacy enabled. Do not add account-specific errors to the public
reset response. The app respects `429` and retains Firebase direct fallback for
service failures, under Firebase's own quotas.

## App Check rollout

Android initializes Firebase App Check after Firebase initialization and before
Auth/Firestore use. Release builds use Play Integrity; debug builds use the debug
provider. Never register/distribute a debug token for a release build. New app
requests carry an App Check token to both custom endpoints. Attestation failures
do not replace an existing Firebase account with a guest during monitoring.
The website initializes reCAPTCHA Enterprise before Auth and Firestore.

The server always rejects an invalid supplied App Check token. Missing tokens
remain accepted during the migration; `APP_CHECK_ENFORCE=true` on the website
rejects them. The Worker forwards attestations to the trusted authorization
service. Firebase's Auth/Firestore enforcement is a separate production setting.
These are migration controls, not a claim that attestation is already enforced.
The reCAPTCHA Enterprise API was enabled and a score-based, domain-restricted
website key registered with Firebase App Check on 12 November 2026. The existing
Android Play Integrity registration was confirmed. The website uses the public
registered key on its production domains; localhost previews do not attest by
default. Auth/Firestore/custom enforcement remains in monitoring until the
updated app has been released and real-device compatibility is validated.

Before turning enforcement on:

1. Verify Play Integrity registration, app recognition, SHA-256 signing
   certificates, Google Play project linkage, and policy for both Play and
   intentionally supported GitHub/sideload builds. Validate on real supported
   devices; emulator tests cannot prove Play Integrity works.
2. Verify the web reCAPTCHA Enterprise key, allowed domains, CSP, and App Check
   registration. The public site-key override is
   `VITE_RECAPTCHA_ENTERPRISE_SITE_KEY`. Monitor valid web requests.
3. Release the new Android build and measure adoption/attestation success.
   Existing released versions do not provide tokens. Enabling enforcement now
   would block their cloud features and password recovery.
4. Enable Firebase Auth and Firestore enforcement and set
   `APP_CHECK_ENFORCE=true` on the website after compatibility is validated.
   Enforcing only the custom reset endpoint leaves the direct Firebase fallback
   subject to the separate Firebase setting.
5. Verify legitimate sign-in, reset, account deletion, backups, AI, and reporting
   still work. Missing, forged, and revoked credentials must fail. Use the
   documented monitoring switches for an operational rollback, not client-side
   bypass credentials.

API keys in clients identify the Firebase project; they are not privileged
credentials. Application/API restrictions should be reviewed separately and
compatibility-tested. A server's native reset REST request may need a separate
API key restricted to Identity Toolkit rather than a browser-referrer-only key.
Do not apply browser restrictions to a key used by an existing backend without
first migrating that backend.

## Dependencies and deployment order

Android explicitly selects `com.google.guava:guava:33.7.2-android`, fixing
GHSA-xxph-c9ww-hj94. The retired Functions lockfile is refreshed to remove its
reported dependency advisories; this does not reactivate or deploy Functions.
The website drops unused SMTP dependencies and updates the vulnerable XML parser.

Deploy/push the website first. Verify `/api/ai-authorize` exists and rejects
unauthenticated POST requests. Then deploy the Worker. A Worker deployed before
its authorization service will fail closed and temporarily stop online answers.
The remaining app changes require a new Android release to reach users.

Tests cover current credential checks, daily quotas, reports, outage behavior,
App Check migration/enforcement, body-size limits, and counter cleanup. The web
suite includes real Firestore emulator tests for concurrent claims, deletion
fences, and update-time delete preconditions. No production test emails, user
data mutations, or real provider questions are needed.
