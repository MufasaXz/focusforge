# Study-only Play release

The approved direction removes parental monitoring from the general study app.
Keep self-selected Shield rules, focus timers, groups and earned achievements.

1. Retire parent onboarding, routes, PIN gates, remote enforcement and all
   app-catalog/progress uploads. Migrate old profiles and clear cached remote
   rules without erasing local study history.
2. Deny retired Firestore paths, retain private achievements and member-only
   groups, and test authorization with the Firebase emulator.
3. Add authenticated server account cleanup with recent-login enforcement,
   complete historical leaderboard cleanup, safe group owner transfer and
   retryable deletion. Supply deployment instructions; the owner deploys rules.
4. Align app and public privacy/deletion copy with actual data handling. Record
   remaining production deployment and Play Console declarations explicitly.
5. Analyze and test Flutter, rules, backend and website; build signed AAB/APK
   with a new version code, verify packaging/signatures, commit and push.

Google Play approval is external. Declarations, live backend/policy deployment,
production deletion verification and device/pre-launch checks remain required.

6. Add community terms/reporting/member hiding for shared user-entered names.
7. Next UI pass: user provided https://dribbble.com/tags/mobile-app-ui as
   inspiration; preserve FocusForge identity and avoid glass cards everywhere.
   Direct fetch returned an empty HTTP 202 response, so no reference was viewed.
