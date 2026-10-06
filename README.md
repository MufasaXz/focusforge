<div align="center">

# 🔥 FocusForge

**An open-source, privacy-first study companion.**
Block the feeds, run the timer, watch the streak grow.

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-a855f7)](CONTRIBUTING.md)
[![Free forever](https://img.shields.io/badge/price-free%20forever-ffd166)](#)

</div>

---

## What this is

FocusForge is four apps in one. A **shield** that strips the endless feeds out
of the apps you lose time to, a **focus timer** that keeps you in the chair,
**analytics** that show where the hours actually went, and a **streak** that
makes you want to come back tomorrow.

It is free, with no ads, no premium tier and no tracking. You do not need an
account — the app works offline, and everything you log stays on your device.

## Screenshots

<div align="center">

| Onboarding | First-run coach marks | Dashboard | Heatmap & weekly |
|:---:|:---:|:---:|:---:|
| ![Onboarding](docs/screenshots/01-onboarding-persona.webp) | ![Coach marks](docs/screenshots/02-coach-marks.webp) | ![Dashboard](docs/screenshots/03-dashboard.webp) | ![Heatmap](docs/screenshots/04-dashboard-heatmap.webp) |

| Shield feed | Whitelist tiers | Restriction profiles | Focus |
|:---:|:---:|:---:|:---:|
| ![Shield](docs/screenshots/05-shield-feed.webp) | ![Whitelist](docs/screenshots/06-shield-whitelist.webp) | ![Profiles](docs/screenshots/07-shield-profiles.webp) | ![Focus](docs/screenshots/08-focus.webp) |

| Timer running | Profile | Strict Mode | Deep Breath Gate |
|:---:|:---:|:---:|:---:|
| ![Timer running](docs/screenshots/09-focus-running.webp) | ![Profile](docs/screenshots/10-profile.webp) | ![Strict Mode](docs/screenshots/11-strict-mode.webp) | ![Breath gate](docs/screenshots/12-breath-gate.webp) |

| Sign in | Daily goal | Study groups | Dark mode |
|:---:|:---:|:---:|:---:|
| ![Sign in](docs/screenshots/13-auth.webp) | ![Daily goal](docs/screenshots/14-daily-goal.webp) | ![Study groups](docs/screenshots/15-study-groups.webp) | ![Dark mode](docs/screenshots/16-dashboard-dark.webp) |

</div>

## Features

### 🛡️ Shield

Block the parts of an app that eat your day without blocking the app.

- **Three ways to block** — strip the feed and leave messages working, put a
  daily time limit on it, or block the whole app. Per app, switchable any time.
- **Grouped by ecosystem** — Instagram, Facebook, YouTube, TikTok, X and more,
  organised by who owns them so you can see what you are actually giving up.
- **A three-tier whitelist** — apps that are always allowed (phone, maps,
  calendar), apps on a daily budget, and apps that are out.
- **Restriction profiles** — Exam Week, Regular Study and Weekend Relax, each
  with its own rules and its own schedule.
- **The Deep Breath Gate** — when you reach for a blocked app, you get a breath
  first. Three slow breaths before you decide. Most of the time you decide not
  to.

### ⏱️ Focus

A timer that is honest about time.

- **Four presets** — Classic Pomodoro (25/5), Deep Work (50/10), Sprint (15/3)
  and Flow State (90/20), each rolling automatically into its own breaks.
- **It survives being backgrounded.** Close the app mid-session and come back
  an hour later: the timer is right, because it counts from the wall clock
  rather than from ticks it may never have received.
- **Subject tagging**, so every session lands against the right subject.
- **A six-channel ambient mixer** — rain, forest, café, waves, fireplace and
  brown noise, with real loops you can layer.

### 📊 Dashboard

Every number comes from your own session log, so the ring, the chart and the
heatmap can never disagree with each other.

- A daily progress ring against the goal you set
- Your current streak
- A weekly bar chart and a five-level focus heatmap
- Per-app usage with a shield toggle on each row
- A subject breakdown bar

### 🏆 Progress

- Levels and XP, earned from focused minutes
- 14 achievements, from your first session to the hundredth hour
- Weekly study goals per subject, with progress rings
- Study groups and a leaderboard once you link an account

### 🔒 Strict Mode

For when you need the decision made in advance.

- Lock the phone for a session — up to eight hours
- **Emergency unlock with friction, not a trap**: type a pledge that you are
  choosing to break your commitment, wait sixty seconds, then confirm. Three
  deliberate steps, no uninstall tricks, and nothing that a store would reject.

### ⚙️ Settings

Study Groups, Achievements, Leaderboard, Strict Mode, Notifications, Data &
Privacy, and About. Appearance follows the system by default, and can be pinned
to light or dark. Six palettes ship — each one a seed pair, so dark mode is a
brighter mix of the same hue rather than a desaturated version of the light
one — plus a true-black mode for OLED panels that moves the surface family and
leaves every accent alone.

## Privacy

Screen-time analytics and usage data stay **on-device**. Everything you log —
your persona, goal, subjects, sessions, shield rules and statistics — lives in
local storage on your phone and is never uploaded.

Linking an account is optional, and the only thing a remote service ever holds
is a credential: an opaque ID, an email address if you gave one, and which
provider you used. No usage data, no screen time, no app lists.

You can export everything as JSON or delete it outright at any time. Deleting
your account removes the credential *and* wipes the local store.

## Getting started

On first launch the app walks you through setup in about a minute — pick a
persona, choose your subjects, set a daily goal, and grant the permissions you
are comfortable with. Every one of them is optional, and the app says plainly
what each is for.

To build it yourself:

```bash
git clone https://github.com/MufasaXz/focusforge.git
cd focusforge
flutter pub get

flutter run                 # desktop, device or emulator
flutter build apk --release # installable Android build
```

Requires **Flutter 3.47+** (Dart 3.13+).

## A note on the shield engine

The shield's rules, tiers, profiles and schedules are all fully built, and the
interface the native blocker plugs into is defined and exercised — but the
Android `AccessibilityService` that actually intercepts app launches is not
wired up yet, so nothing is blocked on a real device today. The app tells you
this in the shield status sheet rather than pretending otherwise.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for how to get set up and what makes a good change. Good first issues are
labelled in the tracker.

## License

[MIT](LICENSE) — free forever, no ads, no tracking, no premium tier.
