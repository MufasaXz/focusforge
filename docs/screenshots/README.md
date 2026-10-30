# Screenshot gallery

The Day and Dark galleries show the current FocusForge interface: Home, Shield,
Focus and You. The two galleries no longer share a capture method, and the
difference is worth stating plainly.

**Dark** was captured on a physical Android device running the 1.0.4 build on
28 October 2026, from the maintainer's own account. The account name, focus
totals, level, badge count and the installed app rows are that account's real
values, published deliberately by the person they belong to. Only the phone
border and the rounded screen clipping are added; nothing in the screen content
is staged or retouched.

**Day** is still the earlier reproducible widget-test render, captured from the
actual Flutter widgets at source commit
20cbb1536e599f540e81914da1011aed98e40929 on 19 October 2026. Those captures
seed a demo subject catalog and a local fixture account, so Alex Morgan,
subject totals, study history and the installed app catalog are demonstration
data, and Android permissions and cloud memberships are not simulated as
working production services.

Neither gallery is manufacturer artwork, and the phone borders in both are
neutral illustrative silhouettes rather than any specific handset.

## Reproduce the images

This reproduces the Day gallery and the Focus motion GIF. The Dark gallery came
off a device and cannot be regenerated from the repository; the four captures it
was built from are preserved in `source/*-dark.png`.

From the app project root, with Flutter and Pillow installed:

```sh
flutter test tool/capture_readme_test.dart
python3 tool/compose_readme_assets.py
```

The capture harness loads the app's bundled text and Material icon fonts, then
renders both actual theme modes at 390 × 844 logical pixels with 2× capture
resolution. It runs outside the default test suite, writes intermediate files to
`build/readme-captures`, and never accesses a user's stored data.

The compositor preserves the original captures in `source/`, linked from the
individual screens in each gallery — 780 × 1688 for the Day renders, and the
device's own 1220 × 2712 for the Dark ones, padded to the frame's aspect with
black rather than stretched. It also resizes them into
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
capture. It is not part of the refreshed four-screen README gallery. The website uses matching updated dark Home, Shield and Focus images. Separate
Play Store artwork and the design-review images are unchanged.
