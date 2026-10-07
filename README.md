<div align="center">

<img src="web/icons/Icon-512.png" width="112" alt="FocusForge">

# FocusForge

**An open-source, privacy-first study companion.**
Close the feeds, run the timer, watch the streak grow.

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-a855f7)](CONTRIBUTING.md)
[![Free forever](https://img.shields.io/badge/price-free%20forever-ffd166)](#)

<img src="docs/screenshots/01-dashboard.webp" width="186" alt="Home">
<img src="docs/screenshots/02-shield.webp" width="186" alt="Shield">
<img src="docs/screenshots/03-focus.webp" width="186" alt="Focus">
<img src="docs/screenshots/04-you.webp" width="186" alt="You">

<sub>Home · Shield · Focus · You — true black, because this is a screen you leave on a desk.</sub>

</div>

---

FocusForge is four things in one app: a **shield** that takes the endless feeds
out of the apps you lose time to, a **timer** that keeps you in the chair,
**analytics** that come from your own session log, and a **streak** that makes
tomorrow easier to start.

It is free — no ads, no premium tier, no tracking — and it works signed out.
Everything you log stays on the device.

## What it does

Every heading below opens: the line is what the feature is, the body is how it
works.

<details>
<summary><b>The shield</b> — close the feed, not the app</summary>

Most blockers are all-or-nothing: you want the feed gone, so you lose the app
with it. The shield draws the line where you draw it.

- **Per-app rules, three tiers.** *Blocked* closes an app as soon as it opens,
  *Time budgeted* gives it the day's allowance and closes it when that is spent,
  and *Always allowed* is for the apps your work runs through. The Apps tab is
  the list of apps you actually installed — a switch applies the moment you flip
  it, with nothing to enable afterwards.
- **YouTube, surface by surface.** Close Shorts while ordinary videos keep
  playing, and remove the recommendation feed while a lecture link still opens.
  Two switches, because "no Shorts" and "no YouTube" are different requests.
- **The Deep Breath Gate.** Reach for a blocked app and you get a 4-7-8 breath
  first. Most of the time, you decide not to.
- **Activity, in plain language.** What was closed, what you walked away from,
  and how long the apps you have rules for were open.
- **It says when a rule cannot fire.** A time budget with no usage access is
  armed but inert, and the status pill says so rather than letting you believe
  you are covered.

The engine is an Android `AccessibilityService` that re-reads its rules from
storage when it starts, so it keeps working while the Flutter engine is not
running.

</details>

<details>
<summary><b>The timer</b> — honest about time</summary>

- **Four presets** — Classic Pomodoro (25/5), Deep Work (50/10), Sprint (15/3)
  and Flow State (90/20) — plus a custom plan you set yourself. Each rolls into
  its own breaks.
- **It counts from the wall clock, not from ticks.** Put the phone down
  mid-session, come back an hour later, and the timer is right. It also writes
  a block into your log when a session finished while the app was not alive to
  watch it.
- **Subjects**, so every session lands against the right one.
- **A six-channel ambient mixer** — rain, forest, café, waves, fireplace, brown
  noise — real loops you can layer, and they keep playing under the session.

</details>

<details>
<summary><b>The clock</b> — five faces, and a full-screen mode</summary>

- **Flip, Segments, Minimal, Analog and Neon.** The analog face runs its hands
  down: they read the time left in the segment, so they meet at twelve as it
  empties.
- **Double-tap the clock** and it fills the screen, either way up. That screen
  draws the session around the window's own edge — a line that starts at the
  middle of the top edge and walks the boundary as the segment runs. A focus
  closes the loop on the last second; a break opens with the boundary whole and
  gives it back.
- **True black reaches it too**, and the wash of phase colour is dropped there,
  because this is the one screen left on for an hour.

</details>

<details>
<summary><b>The dashboard</b> — numbers that cannot disagree</summary>

Every figure is derived from the same session log, so the ring, the chart and
the heatmap can never tell different stories.

- A daily progress ring against the goal you set, and your current streak
- A weekly bar chart, and a five-level focus heatmap
- Per-app screen time with a shield switch on each row
- A subject breakdown, and where today actually went

</details>

<details>
<summary><b>Progress</b> — levels, badges, goals, groups</summary>

- Levels and XP, earned from focused minutes
- 14 badges, from your first session to the hundredth hour
- Weekly study goals per subject, each with its own ring
- Study groups and a leaderboard once you link an account

</details>

<details>
<summary><b>Strict Mode</b> — the decision, made in advance</summary>

Lock the phone for a session, from fifteen minutes to eight hours, and let the
past you decide.

Getting out is possible, and deliberately slow: type the commitment phrase,
wait out a sixty-second cooldown, then confirm. Three steps that take long
enough to think in — no uninstall tricks, and nothing a store would reject.

</details>

<details>
<summary><b>Appearance</b> — six palettes, light, dark, and true black</summary>

Each palette is a seed *pair*: dark mode is a brighter mix of the same hue
rather than a desaturated copy of the light one. Appearance follows the system
by default and can be pinned to light or dark. **True black** moves the surface
family to pure `#000000` and leaves every accent alone — the whole app, the
full-screen clock included.

</details>

<details>
<summary><b>Privacy</b> — what is stored, and where</summary>

Screen time, sessions, shield rules and statistics live in local storage on the
phone. Nothing is uploaded, and the app does not need an account.

Linking an account is optional, and the only thing a remote service ever holds
is a credential: an opaque ID, an email address if you gave one, and which
provider you used. No usage data, no screen time, no app lists.

You can export everything as JSON, or delete it outright. Deleting an account
removes the credential *and* wipes the local store.

</details>

## Under the hood

- **Flutter** for the app. The charts, the motion system and the skeleton states
  are written here — no charting, animation or shimmer package is imported
  anywhere.
- **Kotlin** for the shield: an accessibility service, its own overlay for the
  pause screen, and a rule model that the Dart side only configures.
- **139 tests** across models, providers and screens, including widget tests
  that pump each screen in every state it can be opened in.
- **The screenshots above are not staged.** They come from driving the real
  build through its accessibility tree in a headless browser — the same path a
  screen reader takes, so a control the harness cannot find is a control
  assistive technology cannot find either.

## Getting started

On first launch the app walks you through setup in about a minute: pick a
persona, choose your subjects, set a daily goal, and grant the permissions you
are comfortable with. Every one of them is optional, and the app says plainly
what each is for.

```bash
git clone https://github.com/MufasaXz/focusforge.git
cd focusforge
flutter pub get

flutter run                 # desktop, device or emulator
flutter build apk --release # installable Android build
```

Requires **Flutter 3.47+** (Dart 3.13+). App blocking needs Android; everything
else runs anywhere Flutter does.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for how to get set up and what makes a good change. Good first issues are
labelled in the tracker.

## License

[MIT](LICENSE) — free forever, no ads, no tracking, no premium tier.
