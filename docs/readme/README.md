# README artwork

The hero is original typography and motion artwork using FocusForge's existing
app mark and bundled Inter / Inter Display typefaces. It contains no simulated
application interface. Inter is licensed under the
[SIL Open Font License](https://github.com/rsms/inter/blob/master/LICENSE.txt).

`hero.gif` is a six-second, 1440 × 480 animation with 90 frames at 15 fps and an
infinite loop. Its entire message is readable on the first frame.
`hero-static.png` is the corresponding PNG for reduced-motion or static views.
The composition's frames at exactly 0 and 6 seconds have identical pixels, so
the animation returns to its starting pose. GIF frame durations are quantized
to hundredths of a second; decoded total duration is 5.99 seconds.

The Play Store, GitHub and theme selectors are self-contained SVG image buttons.
Their lettering uses outlined Inter glyphs, preserving the intended font
without external requests. GitHub Markdown supplies their destination links;
the SVGs contain no JavaScript or embedded interaction. The theme selectors
link to dedicated Day and Dark galleries.

The HyperFrames source project is maintained separately from the application
repository. It uses a deterministic, paused GSAP timeline, local assets and
HyperFrames 0.8.150. Rendering used screenshot capture with software graphics.
Automated checks passed for layout, runtime, motion and text contrast.
No physical-device screen or manufacturer render is used in the hero.

The animation was created with the installed
[HyperFrames skills](https://github.com/heygen-com/hyperframes/tree/main/skills).
