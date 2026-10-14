# Play Protect installation block

Policy reviewed October 14, 2026. Applies to the first-release candidate,
FocusForge 1.0.0, and earlier APKs with the optional YouTube service.

Reported warning:

> This app can request access to sensitive data. This can increase the risk of
> identity theft or financial fraud.

Google documents this exact warning in its
[developer guidance](https://developers.google.com/android/play-protect/warning-dev-guidance).
In affected markets, APKs installed from browsers, messaging apps or file
managers declaring certain sensitive permissions, including accessibility,
can be automatically blocked. The wording alone is not evidence of data theft
and it is not an APK signature error.

## What this release changes

- Explicit optional disclosure and agreement before opening Android accessibility
  settings. First-run focus setup does not require this access; Shield requests
  it when the user enables a feature that needs it.
- isAccessibilityTool=false in the accessibility-service XML, the correct
  declaration for a focus tool. No claim to assist disabilities.
- Limited window-change event types and YouTube-only view identifier checks.
  Whole-app detection uses UsageEvents instead of Accessibility. YouTube
  screen checks are not retained or uploaded. No gesture injection, key capture,
  SMS permissions or QUERY_ALL_PACKAGES.
- The existing release signing key is retained for update compatibility.

These changes improve transparency; they **do not guarantee scanner approval**.
Accessibility remains declared for optional YouTube Shorts/feed filtering.
Normal app boundaries use Usage access, Draw over other apps and a visible
user-started foreground service with a Stop action while Flutter is paused. APK signatures verify integrity but do not
exempt sensitive permissions from Play Protect. Changing the package or signing
key to hide from scanning does not resolve the cause.

Usage access is an optional grant for screen-time totals, daily budgets and
whole-app foreground detection. Draw over other apps displays the local pause
screen. The specialUse foreground service needs its honest use-case declaration
and demonstration in Play Console; this is not a guarantee of approval. Play does not mandate a general “app access” setup gate. Keep permission
requests tied to implemented features and explain each grant separately.

## Resolve through review/distribution

Submit the final signed APK for a
[Play Protect appeal](https://support.google.com/googleplay/android-developer/contact/protectappeals).
Include the warning, package dev.focusforge.focusforge, version/build, APK
SHA-256, signing certificate SHA-256, stable APK URL, source repository, and a
video showing voluntary permission consent and shielding. Explain why YouTube
surface filtering requires canRetrieveWindowContent and show screen checks stay
local. Google decides the outcome. No appeal has been submitted from this workspace.

If sharing a direct-install APK through GoFile, include its actual version and
SHA-256. A public download link does not prove Google Play or Play Protect has
approved it, and a rebuilt or newly signed APK must be assessed as that artifact.

Google Play testing/distribution provides a reviewed installation route. A
Play Console release also needs an accurate accessibility declaration, prominent
disclosure/consent, privacy policy and Data safety responses. UI changes and
signing cannot replace those requirements. Disabling Play Protect is not the fix.

See [the submission checklist](play-store-readiness.md) for the still-required
backend and live privacy-page deployment checks, Accessibility review video,
Data safety, account deletion and device testing. Accessibility use is permitted
under Google's [policy](https://support.google.com/googleplay/android-developer/answer/10964491)
for non-accessibility tools with disclosure/declaration; this does not guarantee
approval of a particular implementation.
