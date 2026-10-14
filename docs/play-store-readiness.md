# Google Play readiness: first-release candidate

Policy reviewed October 14, 2026 · FocusForge 1.0.0 · version code 2024.

**Production activation and verification are required before Play submission.**
The in-app deletion path is restored with Spark-compatible client cleanup.
Publish rules/indexes and run the one-time legacy migration, then verify complete
production deletion. Accessibility and special-use service declarations and
real-device checks remain. Google determines approval; this document is not
an approval or security certification.

The displayed version may be 1.0.0 for the first Play release. Keep version code
2024 greater than earlier distributed builds and retain the signing identity.
Changing the display version does not reset Android's update history. Never
reuse a version code already uploaded to this package in Play Console.

## Implemented

- Removed parent setup/persona, pairing, remote control, PIN gates, catalog and
  progress uploads, and guardian navigation. Old profiles retain identity,
  goals, completed setup and history. Focus stays available; old routes redirect.
- Native Shield receives only self-selected local rules. Cached remote rules
  are ignored and replaced at launch. Revised rules prohibit retired monitoring
  writes and permit private owner cleanup. Private achievements and private study groups remain.
- Spark client cleanup covers private badges, inventoried legacy subcollections,
  historical board rows and orphan members. Group ownership transfers; Auth is
  last. An immutable fence blocks stale uploads. No paid backend, TTL or
  automatic background completion is required.
- Accessibility retains optional, separate disclosure/consent and
  isAccessibilityTool=false. First-run setup can finish without granting
  Shield permissions. Timer works without access. Settings, launcher,
  keyboard and emergency access are protected by Shield.
- Account controls include Sign out and Delete account. Confirmation, fresh
  Email/Google verification, loading guard, bounded reauthentication retry and
  local/provider reset are implemented.
- App and website source describe actual cloud data and account controls.

## Technical checks

Build 2024 passed 328 Flutter tests, 33 native tests, 20 Firestore rules tests
and the local migration integration check. A later Home placement/disclosure
check passed at 320dp and 200% text. Final analyzer is clean; signed APK/AAB
builds succeed, APK and all 12 bundled ELF libraries support 16 KB alignment.
Production activation is owner-run and remains unverified here.

On the Android 11 emulator, all four widgets loaded in a native widget host at
140dp with 2× text and exposed their primary values. The weekly widget also
loaded at 280×200dp with native weekday labels and its detailed spoken summary.
This confirms packaged RemoteViews loading, not visual approval across OEM
launchers, Android 16 live surfaces or TalkBack operation.

Target API 36, min API 24, original release signing key. The current official
target policy requires API 36 for new phone apps and updates from August 31,
2026. No SMS/contacts/location or QUERY_ALL_PACKAGES. Normal app shielding declares
SYSTEM_ALERT_WINDOW and a user-visible specialUse foreground service.
Launcher-app visibility uses the MAIN/LAUNCHER query for the actual app picker.
Installed-app information remains sensitive even without QUERY_ALL_PACKAGES;
use it only for the disclosed local feature.

Recheck the final 1.0.0 (2024) merged manifest, signing, AAB and native-library
alignment after building. Checks from 1.0.3 (2021) do not prove the new artifact.
Flutter includes native libraries, so verify 16 KB compatibility in App Bundle
Explorer and on a suitable emulator/device. Use the AAB for Play upload; an APK
download or GoFile link is for direct installation and testing.

## Why each access is requested

| Access | Implemented purpose | Timing and refusal behavior |
| --- | --- | --- |
| Accessibility service | Local YouTube view-ID checks and a pause screen for supported Shorts/feed filters | Separate disclosure and affirmative agreement before Android Settings when a YouTube filter is enabled. Refusal leaves the filter off. |
| Usage access | Local screen-time totals, budgets and foreground-app detection for selected whole-app rules | Request when a user enables normal app shielding or screen-time features. Whole-app rules also require overlay access. |
| Draw over other apps | A pause screen over a whole app selected by the user | Request in context for normal app rules. Missing/revoked access leaves enforcement inactive. No Accessibility grant is needed for this path. |
| Foreground service (specialUse) | Continue local selected-app detection while FocusForge is in the background | Started from the visible app, with a persistent notification and Stop action. Declare and demonstrate this use in Play Console; approval is reviewed separately. |
| Notifications | The user's running timer countdown and subject | Optional. Timer remains usable if notifications are refused. |
| Promoted notifications | Request OS eligibility for a running timer on supported Android/OEM live surfaces | A normal, non-runtime declaration; Android/OEM/user settings decide promotion. Do not promise support for every dynamic bar or island. |

Normal app rules use UsageEvents for foreground detection and an application
overlay for the pause screen. Accessibility is limited to YouTube content
filtering. Overlay access by itself cannot identify the foreground app. This
implementation needs a running native service and both Usage and Overlay access.
Android force-stop and some OEM power management can stop enforcement. Do not
promise immunity from system stop, revocation or uninstall.

Only request permissions for shipped features. Unused Do Not Disturb policy
access and its settings card have been removed from this candidate.

The native countdown uses a notification and BroadcastReceiver. The separate
whole-app shield uses a declared specialUse foreground service with an explicit
subtype explaining local user-selected app shielding. Recheck library-added
services/permissions in the final merged manifest if dependencies change. Respect notification dismissal and
revocation; a running countdown must not repeatedly restore a dismissed update.

## Accessibility declaration scope

Document supported YouTube filters in the Accessibility declaration and
whole-app shielding in the foreground-service declaration and Play listing,
with App functionality as the actual purpose. Do not claim
FocusForge is a disability-support tool. Its rules are deterministic and chosen
by the user, rather than autonomous planning or unrelated automation.

Keep the service's use limited to the declared purpose. Do not add uninstall
protection, prevention of permission revocation, silent Settings changes,
gesture/key capture, or bypasses of Android security controls. Removing the
visible Shield permission banner does not remove the disclosure requirement.

Distinguish data precisely: UsageEvents foreground identifiers and chosen pause
decisions/times are used for local whole-app shielding and insights. YouTube
screen identifiers are checked locally by Accessibility and never retained or
uploaded. While its pause is visible, package-only application-window checks
close the overlay when the user leaves YouTube; other apps’ contents are never
inspected. The watchdog dismisses on lock or an unknown foreground. The disclosure, Android
service description and privacy policy must agree. Saying that *nothing* is
stored would conflict with the local pause history.

## Must finish before submission

1. Publish firestore.rules and firestore.indexes.json, wait for indexes, and
   run the local administrator migration. Verify disposable Email/Google
   accounts' complete deletion. Rules alone do not index historical data. Follow
   [Firebase setup](firebase-setup.md). No Blaze upgrade is required.
2. Deploy website privacy/deletion source to focusforgeorg.vercel.app. Pushing
   GitHub does not prove Vercel deployed. On October 14 the live privacy page
   still displayed October 11 and described parent sharing; the live deletion
   page still described incomplete historical cleanup. Source commit 2bc5d7b
   was explicitly deployed to Vercel on October 14; live privacy/deletion pages
   now serve the current permission and deletion-service guidance. Deployment
   dpl_EgQ3nt3Ma6WouksvDQNNkQXPPv5K is READY. Recheck public URLs before submission.
3. Complete AccessibilityService declaration and real-device review video:
   disclosure, agreement, Settings enablement, supported YouTube filtering,
   refusal and triggering the disclosure again. Also submit the specialUse
   foreground-service declaration/video showing user-started normal app
   shielding, the running notification and its working Stop action. Show every
   disclosure paragraph slowly if it scrolls. Also test revocation. Promo
   footage is not compliance proof.
4. Complete Data safety accurately: Firebase IDs/email/name, private badges,
   optional group membership/minutes/timer deadlines and board name/minutes
   are cloud data. Detailed sessions/usage/screen contents are not uploaded.
   Do not claim no collection or end-to-end encryption. Review Firebase's
   service metadata too. Anonymous Firebase sign-in still sends an account ID
   and contacts the service; an email-free flow does not mean no server contact.
   Local-only processing is excluded from the Data safety collection definition,
   but still belongs in privacy/permission explanations. Assess collection and
   sharing separately using Google's definitions, including service-provider
   and user-initiated-transfer exceptions where applicable.
5. Set privacy/deletion URLs, reviewer access/test-account instructions, no-ads
   declaration, content rating and accurate audience. Community terms, private
   report links and member hiding are implemented. Names visible to other users
   are user-generated content even without chat/media. Verify the report flow
   works with and without an email handler, monitor incoming reports, and remove
   prohibited group/member names using Admin access. Drafting an email does not
   prove effective moderation. Do not select children without Families/consent
   work.
6. Enroll in Play App Signing, register its Firebase certificate, upload to
   internal testing and inspect pre-launch/App Bundle Explorer. Test refusal,
   revocation, Shield, YouTube updates, OEM battery behavior, login, deletion,
   widgets and a 16 KB device. New personal accounts may need 12 opted-in
   testers for 14 days before applying for production access.
7. Monitor the private deletion inbox and failed client deletion reports; verify
   ownership, confirm fulfillment and explain any retention exceptions. The
   external route must remain usable after uninstall without requiring the app
   again. The website must clearly name FocusForge, describe the deletion path
   and disclose retention.

Removing parental monitoring resolves that feature's scope, but Accessibility
review and regional Play Protect sideload screening still apply. Use official
review/appeal routes; do not change keys/package IDs to evade scanning.

## Official references

- [Permissions and sensitive APIs](https://support.google.com/googleplay/android-developer/answer/16558241)
- [Target API](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Accessibility](https://support.google.com/googleplay/android-developer/answer/10964491)
- [User data](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Firebase privacy and service data](https://firebase.google.com/support/privacy)
- [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111)
- [User-generated content](https://support.google.com/googleplay/android-developer/answer/9876937)
- [Monitoring policy](https://support.google.com/googleplay/android-developer/answer/9888380)
- [Foreground services and full-screen intents](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Android foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Background foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Android live updates](https://developer.android.com/develop/ui/views/notifications/live-update)
- [Version codes and names](https://developer.android.com/studio/publish/versioning)
- [16 KB pages](https://developer.android.com/guide/practices/page-sizes)
- [Personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465)
