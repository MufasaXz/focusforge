# Account, progression and layout fixes — 21 October 2026

Branch `1.0.4`, based on `3902629`. The package version remains unchanged in
source; release commands override it to `1.0.0` with build number `2028`.

## Changes

- Interactive email/Google authentication owns recovery while credentials are
  being accepted. Early SDK events cannot start competing recovery. Recovery
  refreshes the credential before loading private backups, and failures still
  keep private account access closed. One recovery overlay uses animated shapes
  and respects the system preference to reduce motion.
- Restored linked profiles are republished to subscribers. A stale profile edit
  cannot overwrite a matching live credential with an anonymous flag.
- Signup requires matching passwords and displays password strength. Reset uses
  Firebase’s built-in reset email and hosted password page, with no custom
  backend, website reset page or new dependency. Unknown accounts receive the
  same app response; delivery/network errors remain visible.
- Account access uses one sign-in action and shorter instructions. Home hides
  subject breakdown until a completed session has an explicit subject.
- Progression starts at 25 focused minutes, grows through 50 levels, retains
  saved progress and overflow XP, and applies five circular avatar-frame tiers.
- Home/Profile widths are bounded on tablets. Profile identity layout uses its
  actual column width; enlarged text and scroll access are tested.

## Verification

- Flutter full suite: **510 passed**; `flutter analyze --no-pub`: no issues.
- Android unit tests: **62 passed**. Firestore rule tests: **30 passed**.
  Functions cleanup/migration emulator tests: **3 passed**.
- Website source: production build and **15 tests passed**. Focused browser
  checks exercised verification using intercepted Firebase responses at
  320, 390 and 1440 pixels, without sending production email.
- Production Node dependency audits for website and Functions: zero reported
  vulnerabilities. Existing development-tool advisories and the earlier
  security review remain separate from production dependencies.
- Java 21 release APK and AAB builds passed with version `1.0.0`/`2028`. APK
  signature verification and AAB bundletool validation passed. Bundle manifest
  has backup, cleartext traffic and debugging disabled. REA inspected final APK
  declarations statically (parent evidence
  `ev_d932ed8e1dae3478436beec0ec894083373fed80f4b8f4b140863488d8a6c967`).
- Android 11 emulator: clean installation succeeded and the launcher activity
  cold-started successfully. Updating an older installation with a different
  certificate was correctly rejected. This is a launch check, not a full
  authentication or performance test. The software-only emulator also reported
  Android System UI/system-process ANRs before installation; those OS dialogs
  prevented reliable visual interaction checks. No FocusForge fatal exception
  was observed in the checked AndroidRuntime log.
- A separate source reviewer found no actionable release-blocking defect in
  the changed flows. Exact `claude-opus-5` CLI review attempts produced no usable
  review output; no substitute Claude model was used.

## Delivery limits

The original release private key was not recovered. Both artifacts use the
existing local Android test key, certificate SHA-256
`2b030d5f5fec0960379a4701114c97465ab24ad133bc05f278f959892d770796`.
They cannot update the original-signed application or replace its Play upload
identity. This test certificate is absent from the Firebase Android certificate
registration; Google OAuth requires the proper registered signing identity.
No certificate was added to production to work around this mismatch.

Firebase’s default hosted email action handler remains configured. The live
verification and password-reset sender names are FocusForge. Enumeration
protection is enabled in Firebase Auth. Client API keys allow the required Auth
APIs but have no application restrictions; those restrictions were not changed.
The new website verification route is
tested local source only: Vercel credentials are unavailable, so the app does
not send users to that undeployed route.

No real inbox, physical phone, full Android/OEM matrix, traffic interception or
penetration test was performed. The review does not establish absence of every
vulnerability. The plaintext app-private storage, device-wide export and
administrative access limits in `security-audit-2026-10-19.md` still apply.
No unrelated native or backend source changes were needed.
