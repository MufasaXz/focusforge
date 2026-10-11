# Screenshot gallery

The Day and Dark galleries each contain four 680 × 1416 PNGs showing actual
Flutter renders of the 1.0.3+2016 application, composed into illustrative OnePlus 15-inspired frames.
They are not physical-device screenshots or official manufacturer renders.
Personal progress and the Demo Student profile are fictional local sample data;
no cloud memberships or leaderboard standings were fabricated.

The capture source tree is `3f74e04d1424a561880812aa79c0ffb7b59633ff`,
shared by the original build-2016 commit and the attribution-only rewritten
commit `1e2f41619b648d99eff8814af238867e54c3d9f3`. Capture-only uncommitted
changes were excluded. Screens were captured at 1272 × 2772 and resized
proportionally for the phone interiors.

The separate Play Store artwork layout and headline treatment reference the supplied
[banner](https://github.com/MufasaXz/che110-ca1/blob/main/IMG_20261011_162251_888.jpg).
Marketing text uses Barlow Condensed Bold and Barlow Regular, licensed under
[SIL Open Font License 1.1](https://github.com/jpt/barlow/blob/main/OFL.txt).
The app's own typography is unchanged.

Phone proportions reference [OnePlus 15 specifications](https://www.oneplus.com/us/15/specs).
Corner radii, camera size and side keys are illustrative, not manufacturing drawings.

PNG decoding, OCR, image geometry and ZIP integrity were checked. The image
bridge did not permit direct visual inspection; no subjective visual approval
or real-device verification is claimed.

The four GitHub gallery files are RGBA PNGs with transparent backgrounds,
not rectangular crops of the Play Store artwork. The original vector phone
body and three side keys are recomposed directly onto transparency; the
paper canvas and paper-colored offset shadow are omitted. No white-color
removal is used, so light app content stays fully opaque.

Original 1080 × 1920 composition geometry: outer body rounded rectangle
`(210,460)–(870,1850)`, radius 54; right keys `(867,702)–(872,802)` and
`(867,824)–(872,883)`, radius 2; left key `(208,670)–(213,721)`, radius 2.
The final 680 × 1416 canvas starts at original coordinate `(200,450)`.
Only the silhouette's anti-aliased edge has partial alpha. Exterior pixels
are transparent, solid frame/screen pixels are opaque, and central screen
pixels were verified byte-for-byte against the source interiors.
All eight output alpha channels match the independently rendered vector
silhouette exactly. Gallery changes do not alter the separate Play Store artwork.

## Day and Dark previews

The original four Day PNGs remain byte-for-byte unchanged at their existing paths.
The four `dark/` PNGs were captured from committed source `55ccc7099146e27cb3af230bc0efc497835c4f83`
in an isolated archive, excluding the working tree's unrelated profile edits.
Its `lib/` tree (`c7915a59e3e8a9d9c994c0b6d3eddf5439f1c247`) is identical to the original Day capture's app source.
The same widget-test harness and fictional local fixtures were used, with
`themeSettingsProvider` set to `ThemePreference.dark` and AMOLED disabled.
`FocusForgeApp` derives its MaterialApp theme mode from that provider, so both
app surfaces and provider-driven components use Dark mode. The capture test passed.
No native-device output, cloud memberships or leaderboard standings are claimed.

Dark images use the exact silhouette, side keys, camera and transparent exterior
of the Day images. Their central interiors were verified byte-for-byte against
the proportionally resized Dark renders, and solid interiors remain opaque.
Dark text is warm off-white; pure-white pixels are not required for this theme.

The README's Day / Dark selector uses GitHub-supported section links and a native
expandable Dark gallery. It is not a JavaScript toggle: GitHub sanitizes scripts
and custom interactive CSS, so selecting a link navigates rather than changing
an in-place image state. Expand “Show Dark phone gallery” to reveal its images.
