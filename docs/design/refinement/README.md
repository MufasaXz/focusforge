# October UI refinement

FocusForge keeps its ember palette, Inter/Inter Display fonts, goal ring and
true-black option. This pass makes the hierarchy and interactions clearer:

- 20dp card corners, sentence-case section headings and consistent spacing.
- A shared 48dp segmented control with a moving tonal selection surface.
- A separate range selector and prominent focus total on the dashboard.
- Daily metrics grouped on one surface, with a stacked layout for large text.
- Profile settings grouped by purpose; long values live below their labels.
- Named palette choices and a shape change when a palette is selected.
- Named ambient tracks with stable placement when playback starts.
- A labelled Start/Pause control where space allows, and softer setup choices.

Every new animation respects reduced motion. Colour follows the live scheme,
and categorical persona, subject and sound hues are harmonized.

## Reference review

The implementation is original Flutter code. No external source, fonts, icons
or other assets were copied. These repositories were reviewed as visual and
interaction references:

| Reference | Useful direction | Repository license at review |
| --- | --- | --- |
| [Dioxamine](https://github.com/rhythmcache/Dioxamine) | Group settings by purpose and use tonal surfaces for hierarchy | Apache 2.0 |
| [Plexo](https://github.com/anmolkapil/plexo) | Give primary metrics room and keep supporting labels quieter | MIT |
| [Kimon](https://github.com/zenzer0s/kimon) | Make the timer action prominent and use deliberate rounded shapes | PolyForm Noncommercial 1.0.0 |
| [UniStack](https://github.com/Kmlozmz/UniStack) | Consistent screen chrome and explicit motion preferences | Proprietary, all rights reserved |
| [Minus](https://github.com/isaacsa51/Minus) | Distinguish numeric values from labels and group related metrics | Apache 2.0 |
| [Deep](https://github.com/shad-ct/deep-peep) | Tactile feedback and readable card labels | No license file found |

## Captures

These are widget-rendered captures using the bundled fonts and fictional local
session data. They document phone and tablet layouts; native Android permission
dialogs and audio playback need device testing.

![Phone screens in true-black mode](overview-dark.webp)

![Phone screens in light mode](overview-light.webp)

![Setup choices](setup-dark.webp)

![Tablet dashboard](dashboard-tablet.webp)

![Tablet profile](profile-tablet.webp)

Regenerate the source PNGs with:

```sh
flutter test tool/capture_ui_test.dart
```

The PNGs are written to `build/ui-review/`. The harness is outside the default
test suite so ordinary tests never rewrite screenshots.

Validation: 204 tests passed, static analysis clean, release web build passed.
Additional checks cover 320dp screens with 2x text, RTL selection semantics,
reduced motion, timer start/pause and restored ambient selections.

## Shield, breathing and social refinement — build 8

The second pass keeps the same typography and colour identity:

- Native Shield uses a stronger heading, framed app icon, clearer reason and
  two explicit actions. Its opaque surface blocks immediately while content
  enters with a short upward fade; Android's animation setting is respected.
- Breathing adds phase seconds, a 4/7/8 guide, gentle tonal transitions and an
  early return action. Reduced motion keeps the disc still and preserves the
  full exercise. Failed launches leave retry/back available.
- Groups now have a real create/join flow, shared weekly progress, member-only
  standings, invite copying, active timer status and leaving/owner transfer.
- Parent views use scheme colours, live code expiry, loading/error states,
  atomic pairing/unlink, per-account rule caching and retrying summary sync.

The following captures use fictional members and explicit provider overrides.
They demonstrate the UI; they do not prove a production Firebase deployment.
No Android device was connected, so native overlay behaviour and Play Protect
clearance have not been verified on a phone. The image viewer did not display
pixels in this environment; layout was checked with widget assertions and
captures were generated for human review.

| Screen | Dark | Light |
| --- | --- | --- |
| Groups | [Capture](groups-dark.webp) | [Capture](groups-light.webp) |
| Group standings | [Capture](group-detail-dark.webp) | [Capture](group-detail-light.webp) |
| Breathing guide | [Capture](breathing-dark.webp) | [Capture](breathing-light.webp) |
| Breathing choice | [Capture](breathing-complete-dark.webp) | [Capture](breathing-complete-light.webp) |
| Parent connection | [Capture](parent-link-dark.webp) | [Capture](parent-link-light.webp) |

Regenerate with: flutter test --no-pub tool/capture_refinement_test.dart

Validation: 213 Flutter tests and nine Firestore emulator tests passed. Static
analysis is clean. The Flutter checks include 320dp/2x text layouts, reduced
motion, handoff order, recovery, UTC totals, queued progress writes, private
membership and cached parent rules. Firebase setup and Play Protect review are
documented separately in docs/firebase-setup.md and docs/play-protect.md.

## Video clock correction — 1.0.3 build 2013

The reference video shows a flat tan dial, fine ticks, serif countdown numerals
and a phase caption below the digits. The earlier Inter countdown, numbered
marks, shaded rim and large hand have been replaced. Login now has a plain
header and sign-in choices, with no clock preview or hero card.

FocusDial-Regular.ttf is a static, digits-only subset of Noto Serif Regular,
licensed under SIL OFL 1.1; the license is in assets/fonts/FocusDial-OFL.txt.
It is bundled for Flutter and Android widget numerals (Android 8+); Android 7
widgets use the platform serif fallback. Pixel comparison against a video
frame selected this font from several open serif candidates. The video's
original typeface and source were not available, so visual identity has not
been proven. Dial fill is sampled from the video at #DCD0B4, with Day backdrop
#F4EADB. Widgets retain the app's subject, countdown and daily-goal data.

Validation: 222 Flutter tests passed; phone/tablet day/dark captures regenerated.
Native launcher runtime still requires a real-device check.


## Clock restoration — 1.0.3 build 2014

At the owner’s request, restored the app dial from before build 2013: bundled
InterDisplay countdown, numbered minute marks, shaded rim and progress hand.
The launcher widgets keep their build 2013 design, subject and daily-goal data.
The clean login is retained. The README still contains exactly four screenshots;
its Focus screenshot now shows the restored app clock.

Validation: clock/widget/login tests, static analysis and regenerated day/dark
captures passed. The release APK has Android v2/v3 signatures, build 2014 and
package dev.focusforge.focusforge. Native launcher behavior needs a phone check.

## Setup polish and Serif face — 1.0.3 build 2015

Wave 2 of the premium pass, on top of build 2014:

- Setup flow: a frosted pinned footer, a per-stage progress stepper, the
  product promise under the splash wordmark, and a tonal celebration hero
  reflecting the user's own choices. Guardian and student branches unchanged.
- Seventh clock face, Serif: remaining time typeset in the bundled FocusDial
  serif with an InterDisplay colon, in the Focus tab, full-screen clock and
  picker. Existing clock selections stay saved.
- Launcher widgets declare picker previews on Android 12+, and the daily-goal
  ring track follows the saved palette instead of a fixed gray.

Validation: 226 Flutter tests passed (4 new serif tests), static analysis
clean, and day/dark/tablet captures regenerated. Widget picker previews and
launcher behavior still need a phone check.
