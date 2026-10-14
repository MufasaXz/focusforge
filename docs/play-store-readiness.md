# Google Play readiness: study-only candidate

October 14, 2026 · FocusForge 1.0.3 · version code 2021.

**Code/build candidate prepared; production submission still needs deployment
and Console/device verification.** Google determines approval and enforcement.
No code change guarantees that a console account will never be suspended.

## Implemented

- Removed parent setup/persona, pairing, remote control, PIN gates, catalog and
  progress uploads, and guardian navigation. Old profiles retain identity,
  goals, completed setup and history. Focus stays available; old routes redirect.
- Native Shield receives only self-selected local rules. Cached remote rules
  are ignored and replaced at launch. Revised rules deny retired monitoring
  data to every client. Private achievements and private study groups remain.
- Authenticated server cleanup covers historical boards, orphan member rows,
  legacy pairing and account subcollections; owner transfer preserves other
  members. Auth is last; private deletion markers block stale writes, hourly
  retries resume failures, and a 24-hour TTL protects old ID tokens.
- Accessibility retains optional, separate disclosure/consent and
  isAccessibilityTool=false. Timer works without access. Settings, launcher,
  keyboard and emergency access are protected by Shield.
- App and website source describe actual cloud data and deletion behavior.

## Technical checks

Target API 36, min API 24, original release signing key. No SMS/contacts/location,
QUERY_ALL_PACKAGES or SYSTEM_ALERT_WINDOW. Signed AAB/APK and verification files
are supplied in the delivery directory. Native runtime requires an adb device;
no device is attached here. Release lint warnings remain documented.

## Must finish before submission

1. Publish firestore.rules and firestore.indexes.json; deploy cleanup functions.
   Verify a disposable account's complete live deletion. **Rules alone do not
   enable the new delete button.** Follow [Firebase setup](firebase-setup.md).
2. Deploy website privacy/deletion source to focusforgeorg.vercel.app. Pushing
   GitHub does not prove Vercel deployed. No usable Vercel login is available.
3. Complete AccessibilityService declaration and real-device review video:
   disclosure, agreement, Settings enablement, selected-app pause, supported
   YouTube filtering and revocation. Promo footage is not compliance proof.
4. Complete Data safety accurately: Firebase IDs/email/name, private badges,
   optional group membership/minutes/timer deadlines and board name/minutes
   are cloud data. Detailed sessions/usage/screen contents are not uploaded.
   Do not claim no collection or end-to-end encryption.
5. Set privacy/deletion URLs, reviewer access/test-account instructions, no-ads
   declaration, content rating and accurate audience. Community terms, private report links and member hiding are implemented;
   monitor reports and remove prohibited group/member names using Admin access. Do not select children without Families/consent work.
6. Enroll in Play App Signing, register its Firebase certificate, upload to
   internal testing and inspect pre-launch/App Bundle Explorer. Test refusal,
   revocation, Shield, YouTube updates, OEM battery behavior, login, deletion,
   widgets and a 16 KB device. New personal accounts may need 12 opted-in
   testers for 14 days before applying for production access.
7. Monitor the private deletion inbox and pending server failures; verify
   ownership, confirm fulfillment and explain any retention exceptions.

Removing parental monitoring resolves that feature's scope, but Accessibility
review and regional Play Protect sideload screening still apply. Use official
review/appeal routes; do not change keys/package IDs to evade scanning.

## Official references

- [Target API](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Accessibility](https://support.google.com/googleplay/android-developer/answer/10964491)
- [User data](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Monitoring policy](https://support.google.com/googleplay/android-developer/answer/9888380)
- [16 KB pages](https://developer.android.com/guide/practices/page-sizes)
- [Personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465)
