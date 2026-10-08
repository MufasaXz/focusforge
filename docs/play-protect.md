# Play Protect installation block

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
  settings, during setup and from Shield.
- isAccessibilityTool=false in the accessibility-service XML, the correct
  declaration for a focus tool. No claim to assist disabilities.
- The same limited event types and YouTube-only view identifier checks. No
  gesture injection, key capture, SMS permissions or all-package visibility.
- The existing release signing key is retained for update compatibility.

These changes improve transparency; they **do not guarantee scanner approval**.
Accessibility is still required for native blocking and YouTube filtering while
Flutter is not running. Four signing schemes verify APK integrity but do not
exempt sensitive permissions from Play Protect. Changing the package or signing
key to hide from scanning does not resolve the cause.

## Resolve through review/distribution

Submit the final signed APK for a
[Play Protect appeal](https://support.google.com/googleplay/android-developer/contact/protectappeals).
Include the warning, package dev.focusforge.focusforge, version/build, APK
SHA-256, signing certificate SHA-256, stable APK URL, source repository, and a
video showing voluntary permission consent and shielding. Explain why YouTube
surface filtering requires canRetrieveWindowContent and show screen checks stay
local. Google decides the outcome. No appeal has been submitted from this workspace.

Google Play testing/distribution provides a reviewed installation route. A
Play Console release also needs an accurate accessibility declaration, prominent
disclosure/consent, privacy policy and Data safety responses. UI changes and
signing cannot replace those requirements. Disabling Play Protect is not the fix.

The v4 .idsig belongs beside the APK for supported incremental installs. It is
not a second app to install and has no effect on this warning.
