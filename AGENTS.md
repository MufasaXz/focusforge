# FocusForge workflow

- Do not change app version/build numbers or create release/version-bump commits unless the user explicitly requests those changes. Asking for ordinary fixes, a build, or a push alone does not authorize a version bump.
- Keep independent changes in focused commits, authored and committed as `mufasaxz <sudeepyadav7272@gmail.com>`, without co-author trailers.
- Do not build an APK or app bundle unless the user requests a build.
- Preserve the user's untracked `bug.md` and `ui-ux-review.md` files.
- Use REA only when the user explicitly requests it.

- This is the `playstore` distribution branch. Keep version `1.0.1` unless the user explicitly authorizes changing the Play version. Do not include GitHub update checks, dialogs, APK installation flows, or the GitHub release version. Cherry-pick shared fixes; do not merge `main` wholesale.
