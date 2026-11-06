# Screenshot gallery

The Day and Dark galleries show Home, Shield, Focus and You from the 1.0.6
build. Both are Flutter widget renders, not device captures. The capture
harness seeds demo data: Alex Morgan, a week of Maths, Physics and Chemistry
sessions, and Shield rules for Instagram, YouTube, WhatsApp and Snapchat. None
of it comes from a real account.

The Dark gallery uses the pure black (AMOLED) theme. Each render sits in the website's OnePlus 15 frame (`op15.css` from
focusforge-web) with an Android status bar and gesture pill drawn on top.

## Reproduce the images

From the app project root, with Flutter installed:

```sh
CAPTURE_SCALE=3 flutter test tool/capture_redesign_test.dart
```

This writes 1170 × 2532 captures to `build/redesign`. Copy
`{dashboard,shield,focus,profile}-{light,dark}.png` into `source/` here and
into the store compositor's `shots/` folder, then run the compositor. It lives
outside this repository, in the maintainer's `~/project/art/store`, and uses
Playwright's Chromium from focusforge-web:

```sh
node readme.mjs path/to/focusforge/docs/screenshots
```

It writes `gallery-day.png` and `gallery-dark.png` (2620 × 1340, transparent
so either GitHub theme shows through) and the eight single phones
(680 × 1416): `01-dashboard.png` … `04-you.png` for Day and the same names in
`dark/` for Dark.

The Focus motion GIF (`03-focus.gif`) is older and comes from
`tool/capture_readme_test.dart` and `tool/compose_readme_assets.py`.

## Store images

The README's two rows of screenshots are six of the Google Play store images
from the same compositor (`node render.mjs`), in the pure black (AMOLED)
theme. Each puts a 1.0.6 capture with demo data in the website's phone frame,
under or over its Play Store headline. Every row is one image,
`store/row-1.webp` and `store/row-2.webp`: three images at 600 px wide with
rounded corners and 36 px transparent gaps, so the three stay side by side at
any screen width.
