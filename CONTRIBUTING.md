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

Requires Flutter 3.47+ (Dart 3.13+). The dependency list is deliberately short
— please open an issue before adding a package, and say what it does that the
hand-written code cannot.

## Before you open a PR

```bash
flutter analyze                                        # must be clean
flutter test                                           # must pass
flutter build web --release --no-web-resources-cdn     # must build
```

`--no-web-resources-cdn` bundles CanvasKit locally instead of pulling it from
gstatic, which makes local previews fast and deterministic.

Please include a screenshot or short screen recording of any visual change.

## Design rules

The UI is Material 3 with a small set of non-negotiable conventions. If you are
touching the interface, follow these:

1. **Everything comes from the colour scheme.** `AppTheme` builds both themes
   with `ColorScheme.fromSeed`, so no widget should contain a hard-coded hex
   value. Pick the role that means what you want — `surfaceContainer` for a
   panel, `onSurfaceVariant` for supporting text, `outlineVariant` for a
   divider. If you find yourself wanting a new colour, you probably want a
   different role.

2. **Categorical colour is the one exception, and it is harmonised.** A
   subject's hue, a whitelist tier's green/amber/red and a persona's tint carry
   meaning and have to stay distinguishable, so they cannot become scheme
   roles. Pass them through `harmonize()` at the render site so they sit in the
   live theme's temperature instead of clashing with it.

3. **Blur in exactly three places.** A real `BackdropFilter` is expensive and
   it is reserved for surfaces that genuinely float over scrolling content:
   the navigation bar (σ20), bottom sheets and dialogs (σ24), and the Deep
   Breath Gate (σ30). Everything else is a solid tonal surface.
   `MaskFilter.blur` is not used anywhere — a coloured glow is the tell that a
   surface is decoration rather than hierarchy.

4. **Icons, not emoji.** Emoji render at different weights and sizes on every
   platform and instantly make an interface look assembled rather than
   designed. Use Material glyphs in an `IconBadge`.

5. **Motion: fast in, springy out.** Presses scale down in ~90 ms and release
   on an overshoot curve over ~340 ms. Entrances use `easeOutCubic`. Every
   animation must honour the platform "reduce motion" switch.

6. **Hit targets stay at 48 dp** even when the visual element is smaller.

7. **Use the shared chrome.** New settings screens should start from `AppPage`
   and `AppSection` rather than assembling their own scaffold, so eight screens
   cannot drift apart.

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

The app is complete as a front end. The one thing missing is the native shield
engine — the Android `AccessibilityService` that actually intercepts app
launches. The interface it plugs into (`ShieldPlatformService`) is defined and
exercised, so that work is additive rather than a rewrite. Anything else that
needs native platform channels or a backend is worth an issue before you start.

## Code of conduct

Be decent to each other. Harassment, discrimination and personal attacks are
not welcome here.
