# Screenshot gallery

The Day and Dark galleries show the current FocusForge interface: Home, Shield,
Focus and You. They were captured from the actual Flutter widgets at source
commit `00a1cc820d0bf0523c18ecb50525c2752be4f513` on 13 October 2026. The app
`lib/` tree was `4b0ed22ed7fddc9d2ef1e5f6c84be9f1ec96a485`.

These are reproducible widget-test renders with fictional local fixtures,
composed inside neutral illustrative phone borders. They are not physical-device
screenshots or manufacturer artwork. Alex Morgan, subject totals, study history
and the installed app catalog are demonstration data. Android permissions and
cloud memberships are not simulated as working production services.

## Reproduce the images

From the app project root, with Flutter and Pillow installed:

```sh
flutter test tool/capture_readme_test.dart
python3 tool/compose_readme_assets.py
```

The capture harness loads the app's bundled text and Material icon fonts, then
renders both actual theme modes at 390 × 844 logical pixels with 2× capture
resolution. It runs outside the default test suite, writes intermediate files to
`build/readme-captures`, and never accesses a user's stored data.

The compositor preserves the original 780 × 1688 captures in `source/`, linked
from the individual screens in each gallery. It also resizes them into
680 × 1416 transparent PNGs.
Only the border and rounded screen clipping are added; the app's controls, text,
colors and layouts come directly from the Flutter render. Screen content stays
opaque, including light surfaces. The transparent exterior is created from a
vector silhouette rather than removing white pixels. No camera hole covers app
content.

`gallery-day.png` and `gallery-dark.png` combine the four matching phone renders
on transparent 2620 × 1340 canvases. Their Home, Shield, Focus and You captions
use the app's bundled Inter typeface on opaque caption backgrounds that remain
readable against either GitHub theme. The Day and Dark buttons open `day.md`
or `dark.md`, where readers can switch to the other gallery or return to the
main README.

`03-focus.gif` is a 340 × 708 animation of the actual Focus Start control being
pressed and released. It captures the real app transition at about 12 frames
per second, with pauses at the beginning and end. It does not fabricate an
accelerated focus countdown. Its palette is shared across frames to keep the
static interface steady.

## README theme selector

GitHub supports section links, expandable `<details>` galleries and
theme-sensitive `<picture>` images. The README uses these supported elements;
it does not depend on custom JavaScript, custom CSS or an embedded app. GitHub
controls the surrounding font styling.

## Validation and older artwork

The fresh Flutter capture test passed. PNG/GIF decoding, dimensions, transparent
exteriors, central screen pixels and readable screen labels were checked. The
image bridge did not provide direct visual inspection, so no subjective visual
approval or native-device verification is claimed.

The older `04-groups.webp` remains an unused local-fixture preview from a prior
capture. It is not part of the refreshed four-screen README gallery. Separate
Play Store artwork and the design-review images are unchanged.
