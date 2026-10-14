# Google Play readiness audit

Audit date: October 14, 2026. Candidate: FocusForge 1.0.3, version code 2020.

**Status: not ready for a production submission.** The build meets the checked
technical requirements, but the policy and operational items below remain.
This audit does not represent Google Play approval.

## Fixes in this candidate

- The full public privacy policy opens from account creation and Account &
  privacy. If a browser cannot open, the URL is copied with an explanation.
- An external account-deletion request link is available from Account & privacy.
- Parent pairing requires agreement before creating a code. The disclosure
  names study summaries, app names/package IDs, Firebase, the receiving parent,
  background sharing, and how to stop the feature.
- Anonymous sign-in no longer claims that skipping an email account keeps
  everything offline. Detailed study logs remain local.
- The permissions page describes supported YouTube filtering without promising
  Instagram Reels surface filtering.
- Usage-access checks use the API available on Android 7–9, avoiding an
  unguarded API 29 call discovered by Android lint.
- Website policy source now describes private achievement backups and the
  current cloud-deletion flow, including historical-record limitations.

## Checks completed

- Target SDK 36 / Android 16, minimum SDK 24. API 36 meets the submission
  requirement effective August 31, 2026.
- Release signing material is ignored by git. The existing release key is
  retained; no debug signing fallback is configured.
- No SMS, contacts, location, all-package-query or draw-over-apps permission.
  Accessibility declares isAccessibilityTool=false, only window events and
  view IDs; YouTube content inspection is scoped to its package.
- Android App Bundle build and bundletool validation; native packaging requests
  PAGE_ALIGNMENT_16K. Native ELF load alignment is checked separately.
- 284 Flutter tests passed, including deletion failure, returning accounts,
  density/layout, and permission gates. After the final small corrections,
  31 affected tests passed, followed by 28 account/consent/layout tests after
  adding policy links to every account-creation sheet. Analysis reports no issues.
- Android release lint passes with zero errors. It still reports warnings
  including small widget text, untranslated strings and optional attributes
  ignored on older Android versions.
- All 24 Firestore emulator authorization tests passed. These test the checked-in
  rules, not the deployed Firebase project.
- Website production build and all 13 tests passed. The public privacy and
  deletion URLs return HTTP 200.

## Submission blockers and owner actions

1. **Parent monitoring policy.** Study summaries and installed-app information
   are transmitted to another person. Google Play's monitoring-app policy can
   apply. The current general-purpose study app does not establish the required
   monitoring-app designation, ongoing notification, or an exclusively parental
   product/listing. Consent alone does not resolve this. Decide between a
   study-only Play build without remote parent sharing, or a separately scoped
   parental product with the required declarations and review. Do not add a
   manifest label merely to imply approval.
2. **Complete associated-data deletion.** The app deletes current parent links,
   shared records, private badges, group rows, and leaderboard weeks recovered
   from local history before deleting the credential. Historical leaderboard
   entries from other devices and old pairing-code records can remain. A trusted
   cleanup process or a verified manual process must cover them. Authentication
   deletion alone is not a Firestore cascade. No live deletion job or end-to-end
   production cleanup has been verified here.
3. **Deploy the privacy update.** The app links to
   https://focusforgeorg.vercel.app/privacy, with deletion requests at
   https://focusforgeorg.vercel.app/delete-account. The live Vercel deployment
   was still serving an older build when checked. Its policy omitted achievement
   backups. The updated website source needs production deployment. Local Vercel
   CLI credentials are absent; a git push has not been verified to deploy it.
4. **Firebase production verification.** Confirm that the reviewed rules are
   deployed, account login works with the Play signing certificate, and badge
   restore/parent-group deletion succeed against the production project.
5. **Play Console declarations.** Complete AccessibilityService declaration and
   review video, Data safety (including Firebase identifiers, email/name,
   achievements and optional social/parent data), privacy/deletion URLs, app
   access instructions, ads declaration, content rating, and target audience.
   Do not claim no data collection because detailed sessions are local. Do not
   select children as an audience without the applicable Families/consent work.
6. **Console and device checks.** Enroll in Play App Signing, upload the AAB to
   internal testing, check the pre-launch report and App Bundle Explorer, and
   test accessibility, OEM background behavior, account deletion, and a 16 KB
   device. No adb device was attached for native runtime verification. New
   personal accounts may need 12 continuously opted-in closed testers for
   14 days before applying for production access.
7. **Manual deletion inbox.** Verify that the published private email address is
   monitored, ownership is verified safely, all related records are removed,
   and fulfillment/retention details are communicated. An email link does not
   establish that this operational process works.

## Official references

- [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [16 KB page-size compatibility](https://developer.android.com/guide/practices/page-sizes)
- [AccessibilityService policy](https://support.google.com/googleplay/android-developer/answer/10964491)
- [User data, privacy and consent](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Monitoring applications / malware policy](https://support.google.com/googleplay/android-developer/answer/9888380)
- [Monitoring-app declaration](https://support.google.com/googleplay/android-developer/answer/12955211)
- [Testing for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
