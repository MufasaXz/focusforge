# Pip’s offline study tutor

Pip now bundles 63 authored lessons covering maths, physics, chemistry,
biology, computing, writing, and study techniques. Lessons include a checked
example, a common misconception, and multiple-choice practice with explanations.
The existing local reports, timers, app-blocking controls, exam countdowns,
reminders, and editable plan cards remain available.

This is an expansion of the deterministic on-device engine. No language-model
weights were trained, no personal data is used for training, and no model or
dataset download is required. More time spent running the app does not teach it
new facts. It cannot answer every academic question or confirm a current exam
syllabus. Its authored content and algorithms must be reviewed when expanded.

## What students can ask

| Capability | Example |
| --- | --- |
| Concept explanation | `explain derivatives` |
| Simpler explanation | `simpler` after a lesson |
| Worked example | `worked example` after a lesson |
| Compare concepts | `compare mitosis vs meiosis` |
| Recall cards | `flashcards on genetics` |
| Keyed practice | `quiz me on fractions` |
| Hints and feedback | `hint`, `A`, `show answer` |
| More difficult practice | `harder` or `quiz me on derivatives advanced` |
| Exact available-time plan | `I have 1 hour 30 minutes for Maths` |
| Custom block lengths | `I have 90 minutes, 20/5 pomodoro` |
| Clock-window budget | `plan from 6:30 pm to 8 pm` |
| Arithmetic | `calculate (12 + 8) / 5` |
| Linear equation | `solve 4(2x-1)=3x+11` |
| Quadratic equation | `solve x^2-5x+6=0` |
| Percentages | `percentage change from 80 to 100` |
| Statistics | `median 1, 4, 2, 9` |
| Units | `convert 2 km to m` |

Topic retrieval handles selected Hindi/Hinglish aliases and one-edit errors in
long topic words. This does not amount to full multilingual tutoring; the
expanded authored explanations are currently English. Existing translated
timer/report flows remain unchanged.

## Practice and calculations

Sixteen topic families generate parameterised numeric questions after their
authored bank. Other topics stop when their bank ends and suggest another topic.
They do not pretend to generate unlimited new factual questions.

Hard exercises include chain-rule differentiation, integration by substitution,
equations with brackets and variables on both sides, successive percentage
changes, perpendicular-vector constraints, two-stage motion, combined resistor
networks, and limiting-reactant calculations. Answers are computed, with four
distinct options. Hints, a second attempt, and worked feedback support learning.

Two unassisted first-try successes raise the requested practice difficulty;
an incorrect or assisted answer reduces it. Students can also ask for `harder`
or `easier`. The displayed score is a short practice check, never a mastery,
grade, exam-readiness, or diagnostic claim. Reveals, hints, and repeated attempts
do not receive unassisted first-try credit.

The maths parser supports bounded arithmetic and linear/quadratic polynomials
in `x`, parentheses, integer powers from −12 to 12, numeric `sqrt`/`abs`, and
`pi`. It rejects variable denominators, higher-degree intermediate expressions,
undefined operations, excessive nesting, and unsupported notation. Results use
floating-point arithmetic and are rounded for display; it is not a symbolic
algebra system or a proof checker. Numeric unit conversions cover matching
length, mass, volume, time, and temperature units, not currency or live data.

Available-time plans include every break in the stated budget, accept compound
and decimal durations, cap a single plan at eight hours, and honour named saved
subjects. Unnamed priorities come from logged-time deficits, not inferred
academic ability. Text-only coaching does not start a timer, change a saved
goal, or create a reminder. Existing explicit action chips retain those flows.

## Privacy and safety

The tutor has no HTTP, Firebase, native platform, model-runtime, or filesystem
dependency. It receives a local study snapshot from the existing controller.
Recognised tutoring messages stay local even with Cloud Study Coach enabled,
and are excluded from later cloud conversation history. Optional account sync
elsewhere in the app remains a separate feature.

The active lesson, question, hint/attempt state, and small practice score exist
only in the controller’s memory. They expire for follow-up interpretation after
20 minutes, and clear on chat clearing, account/provider reset, or an unrelated
action. No new SharedPreferences/database key or tracking SDK was added.

Fixed safety responses precede cloud routing and command execution for recognised
self-harm, harmful-content, cheating, instruction-extraction, and unsafe
all-night-study requests. Crisis copy encourages immediate support from a
trusted person and local emergency services. These rules are conservative,
language-limited guards, not a claim of perfect detection or medical care.

## Pip’s movements and Home thoughts

Pip has 24 additional learning thoughts alongside the existing observations.
Greetings and thoughts share the persisted `lastTipAt` cooldown: at least six
hours between unsolicited messages, at most one per Home visit. Quiet mode and
an active focus timer suppress them. User-created due reminders retain their
separate reminder policy.

Idle fidgets now wait 12–20 seconds initially and 14–24 seconds between attempts,
avoid consecutive identical choices, and yield to deliberate gestures. Arm and
sitting springs are more damped, weight shifts ease in/out at rest, hops are
smaller, and opening chat gives a small nod. Posture changes stop incompatible
foot swings and stretches. Sleep cancels stale gesture clips. Reduced motion
still holds poses without animation; all animated clips finish and settle.

## Verification

Run with the project SDK environment:

```sh
source /home/aosp/project/sdk/env.sh
flutter analyze --no-pub
flutter test --no-pub
```

Tests cover every lesson’s retrieval and answer-key shape, 1,500 generated
question variants, independently solved linear/quadratic equations, numerical
derivative/integral cross-checks, every minute budget from 0–480, malformed and
adversarial input, quiz scoring/expiry, signed numeric grading, cloud-history
isolation, consent, Home cooldowns, and finite/reduced-motion animation behavior.

Verified on 2026-11-14: all 894 default Flutter tests passed, the separate
light/dark/AMOLED capture harness passed, and `flutter analyze --no-pub`
reported no issues. Review images are local build artifacts in `build/pip/`,
including `chat-offline-{lesson,quiz,maths,budget}-{light,dark,amoled}.png`.
