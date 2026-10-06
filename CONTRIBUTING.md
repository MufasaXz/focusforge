# Contributing to FocusForge

Thanks for wanting to help. FocusForge is free and open source forever, and
every contribution — code, design, docs, translations, bug reports — is
welcome.

## Getting set up

```bash
git clone https://github.com/MufasaXz/focusforge.git
cd focusforge
flutter pub get
flutter run            # device or desktop
flutter run -d chrome  # browser
```

Requires Flutter 3.47+ (Dart 3.13+). The project has **zero third-party
dependencies** and we would like to keep it that way — please open an issue
before adding a package.

## Before you open a PR

```bash
flutter analyze          # must be clean
flutter build web --release --no-web-resources-cdn   # must build
```

There is no test suite yet (Phase 1b adds one); until then, please include a
screenshot or short screen recording of any visual change.

## Design rules

The UI is a glass system with a small set of non-negotiable conventions. If you
are touching the interface, follow these:

1. **Use the tokens.** Colours, radii and spacing all live in
   `lib/app/theme/color_tokens.dart`. No hard-coded hex values in widgets.
2. **Respect the alpha rule.** `Color.withValues(alpha:)` *replaces* alpha, it
   does not multiply it. Calling it on an already-translucent token produces an
   almost-opaque white and flattens the surface. Scale from the token's own
   alpha — see `GlassTokens.glassL2At`.
3. **Blur sparingly.** A real `BackdropFilter` is expensive. It is reserved for
   surfaces that genuinely float over scrolling content — the nav bar, the
   session dock, the Shield header, sheets. Everything else fakes it.
4. **Icons, not emoji.** Emoji render at different weights and sizes on every
   platform and instantly make an interface look assembled rather than
   designed. Use Material glyphs in a `GlassIconBadge`.
5. **Motion: fast in, springy out.** Presses scale down in ~90 ms and release
   on an overshoot curve over ~340 ms. Entrances use `easeOutCubic`.
6. **Hit targets stay at 48 dp** even when the visual element is smaller.

## Commit messages

Conventional-ish prefixes, imperative mood:

```
feat(shield): add per-app time budgets
fix(nav): stop indicator clipping on narrow screens
docs: correct the web build flag
```

## Reporting bugs

Include your Flutter version (`flutter --version`), the platform, and steps to
reproduce. Screenshots help enormously for anything visual.

## Scope

This repo is the **UI shell** right now. Before building a feature that needs
native platform channels or a backend, open an issue first — the phasing is
deliberate and documented in the README roadmap.

## Code of conduct

Be decent to each other. Harassment, discrimination and personal attacks are
not welcome here.
