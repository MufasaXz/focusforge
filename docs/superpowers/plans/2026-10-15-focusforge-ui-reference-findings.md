# FocusForge UI reference investigation

Date: 2026-10-15. Scope: inspect official shipped APKs for concise onboarding, safe item management, and social identity hierarchy. The reference APKs are not copied into the FocusForge source tree. No reference artwork, branding, or source is being copied.

## Provenance

| App | Official source | Package / version verified by REA | SHA-256 |
| --- | --- | --- | --- |
| Loop Habit Tracker | https://github.com/iSoron/uhabits/releases/download/v2.3.1/loop-2.3.1-release.apk | org.isoron.uhabits / 2.3.1 (20301) | e3da224511dc61cda2e8d55f400ea4be51f58afceba832717a833a143832bc1a |
| Medito | https://github.com/meditohq/medito-app/releases/download/v2.0.48/medito-v2.0.48.apk | meditofoundation.medito / 2.0.48 (20048) | 7d602e1dca058152f4dae37c49dc1a8c223c0d5d8cea2cc5746f2beb56e434c9 |
| Habitica | https://github.com/HabitRPG/habitica-android/releases/download/4.4/7971.apk | com.habitrpg.android.habitica / 4.4 (7971) | 960a24f9ffeb7258ff628f2ca470c52ac8feb91ed4f7b2540a05400e8b5de2b8 |

Habitica 4.4 is the most recent official release with an APK asset among the 20 release records queried; newer release records had no assets. Medito is the version supplied by its latest GitHub release and is an old build. Neither is claimed to represent the current Play Store design. APK signature verification was outside this research scope; official HTTPS release provenance and SHA-256 were recorded.

REA MCP tools were absent in this worker. Analysis used the public, pinned `npx -y rea-agents@6.4.0` CLI, existing JADX headless MCP JAR 0.7.1, and JDK 17. No REA configuration or registration was changed. Full JSON evidence is saved beside this document. Package downloads used curl from the official URLs; REA performed package, class, method, install, launch, and screen observations.

## Findings and recommended adaptations

1. **Loop onboarding has one idea per screen.** `IntroActivity.onCreate` declares three slides, each a title, a description, and an illustration. Its first runtime UI tree contained Welcome, one short sentence, an image, and Skip / Next controls. Adaptation: each FocusForge setup screen should lead with the decision, keep one short helper sentence, and move optional explanation to the relevant control. This supports removing repeated eyebrows, explanatory paragraphs, and decorative selected-card shadows. It does not establish that all onboarding must have three screens.

   Static evidence: `loop-intro-oncreate.json`, `ev_35b9bfe39b5f7ed81ba63142feea3e48ff0e0d19b95315a21761c21abc6d765d`. Runtime capture: `loop-initial-screen-evidence.json`, `ev_68a10ee0874c670a6e6851436280f4d18036da454b9b7c5847a9733a2ca6dd87`. UI tree: `loop-initial-ui.xml`. Packaged text was also read using Android SDK aapt2; that resource dump is ordinary shell evidence, not REA evidence.

2. **Loop separates selection from destructive confirmation.** `ListHabitsSelectionMenuBehavior.onDeleteHabits` calls a delete-confirmation screen and supplies selected count. Adaptation: give FocusForge a visible Manage subjects action and a clear confirmation that explains retained study history. Preserve completed sessions when removing a subject from active choices. FocusForge historical retention is our product decision, not a claim about Loop's deletion semantics.

   Static evidence: `loop-delete-method.json`, `ev_3434972194441baebc2040cc88ae9333a9d291785f5967de32dbc68bbb03edef`.

3. **Habitica social rows give identity and self-status separate roles.** `GroupMemberViewHolder.bind` assigns an avatar, display name, and level subline. When the row is the current user, it shows a You pill and hides its more menu; other users get the menu. Its packaged party-member layout places the avatar next to a text column and places the status / menu at the row edge. Adaptation: use a clearer avatar/name/level group on FocusForge's weekly board, a distinct You badge, a strong duration value, and existing report/hide actions for others. Top-three rank decoration and a separate personal-standing card remain original FocusForge design choices.

   Static evidence: `habitica-member-bind.json`, `ev_376dcddd452128133930ae6bd0f91389a093e392af130e58c32b99f5ef138277`. Layout: `habitica-party-layout.txt` from aapt2 (ordinary shell evidence). The bind decompilation includes JADX switch warnings in class-icon handling; the avatar/name/level/self-pill observations precede that warning area. A complete case-sensitive class-name search for Leaderboard returned no matches; this is a social-row reference, not an observed Habitica leaderboard.

4. **Medito yielded limited useful design evidence.** The runtime tree showed Good afternoon, a menu action, and two primary tabs Home / Packs; its remote content stayed blank through the bounded capture. It demonstrates a small number of visible top-level destinations, but supplies no reliable onboarding or leaderboard reference for this task. No richer Medito UI claim should be made. JADX observes the Android host of this Flutter app and does not reconstruct its Dart interface.

   Package evidence: `medito-package-evidence.json`, `ev_93780cbb2bf7b8b365135f590321d08aecab86cc737c466c42f6de7657a0e664`. Capture: `medito-initial-screen-evidence.json`, `ev_c074abf65be170f02a01ba8d920d3e3f6827a87f8584ef7f610dadb1d4416a18`. UI tree: `medito-initial-ui.xml`.

## Research boundaries

Static observations establish declarations and recovered code, not successful execution. Runtime observations were limited to first-launch screens on emulator-5554 (Android 11, 320 x 640). Loop and Medito were installed as separate packages; FocusForge package/data were not modified. FocusForge was brought back to the foreground after capture. Habitica was inspected statically and was not installed. Screenshots were retained with digests; this worker's image-display tool did not render them visibly, so runtime content claims above are grounded in the UI tree rather than a claimed visual review.

Answered: concise onboarding structure, explicit destructive confirmation, social identity / level / self-status hierarchy. Partly answered: visual styling reference (static layouts plus retained captures). Unresolved: current Medito content and actual leaderboard runtime reference. FocusForge's requested leaderboard redesign can proceed as an original design informed by the observed social-row pattern.
