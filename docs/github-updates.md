# GitHub and Google Play releases

`main` is the GitHub edition. `playstore` is the Google Play edition, currently
1.0.1+3001. Both include the shared profile, Focus and Shield fixes. The Play
branch excludes the GitHub updater files, startup hook and About update row;
it makes no automatic GitHub release-check request.

Cherry-pick shared fixes into both branches. Do not merge all of `main` into
`playstore`, since that would import the updater and GitHub version. Version
and build-number changes still require an explicit user request.

## Publish a GitHub update

1. With explicit release authorization, update `pubspec.yaml` and both constants
   in `lib/core/app_version.dart` together. Every build must have a larger Android
   version code, including a rebuild of the same marketing version.
2. Run analysis and tests, then build the signed, obfuscated release APK. Keep
   private Dart symbols and R8 mappings outside the distributed artifacts.
3. Tag the exact tested source. Use `1.0.8` for a new version, or `1.0.7+3004`
   for a newer build of 1.0.7. Replace an existing APK only when explicitly
   requested by the owner; replacement at the same version/build does not
   trigger a new-version notice for installations already on that build.
4. Attach the universal APK as `FocusForge-<version>.apk`, e.g.
   `FocusForge-1.0.8.apk`. Add `<!-- focusforge-build: 3005 -->` to the release
   notes, using the packaged Android version code. This metadata is invisible
   in rendered notes and lets the checker detect newer builds without adding
   the build number to the filename. Keep one APK asset, and verify its GitHub
   SHA-256 digest against the local file. Older build-number filenames remain
   recognized for compatibility. Upload assets to a draft before publishing.
5. Publish as a stable release and mark it **Latest**. The updater checks the
   GitHub `/releases/latest` API; drafts and prereleases are ignored. Releases
   without a matching, fully uploaded APK are ignored too. Start notes with the
   Google Play link and finish with https://t.me/FocusforgeApp.

## What users see

On Android, a launch/resume check runs at most once per 24 hours. The prompt is
deferred during a running focus session, sign-up or account changes, and while
another dialog/settings page is open. Each eligible version/build is shown
once. Later, Back and outside-tap dismiss it. About → Check for updates can find
a dismissed release again. Network failures do not block the app.

The user opens the official release page to download and install the APK using
Android's normal installer. This feature does not silently install software,
request install-package privileges or replace Play's update mechanism. Android
still enforces package identity and signing certificates.

Only HTTPS requests to public GitHub release metadata are made; responses have
an 8-second timeout and 256 KiB limit. Version and build comparisons prevent
downgrade prompts. Release and asset URLs must belong to this exact repository.
No account credentials, device ID, study metrics or app lists are transmitted.
GitHub sees the request's IP address and generic client headers. The check time
and shown release/build are local preferences, included in normal local erasure.

This updater first ships in 1.0.7. Existing 1.0.6/earlier installations cannot
display it until the user installs a version containing the feature. It is not
a push notification: publishing while the app stays foregrounded does not
immediately display a dialog.

Echo Music was reviewed only as a behavior reference. No GPL source or assets
were copied; the Flutter implementation is original FocusForge code.
