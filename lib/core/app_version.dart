/// The app's marketing version, shown wherever a build is named.
///
/// Kept in step with `pubspec.yaml`'s `version:` by hand: the app ships no
/// `package_info` dependency, so one constant is the whole mechanism. The three
/// places that display it — the About screen, the profile's About row and the
/// licences page — used to hold their own copies, which is how the readouts
/// drifted a release behind the build.
///
/// Google Play counts its own versions from 1.0.0, while GitHub releases carry
/// on from 1.0.5. A GitHub build passes its number with
/// `--build-name=1.0.6 --dart-define=APP_VERSION=1.0.6`; a Play build passes
/// nothing and shows pubspec's version.
const kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.1',
);
