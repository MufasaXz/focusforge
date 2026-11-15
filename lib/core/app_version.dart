/// The app's marketing version, shown wherever a build is named.
///
/// Kept in step with `pubspec.yaml`'s `version:` by hand: the app ships no
/// `package_info` dependency, so one constant is the whole mechanism. The three
/// places that display it — the About screen, the profile's About row and the
/// licences page — used to hold their own copies, which is how the readouts
/// drifted a release behind the build.
///
/// The main branch ships GitHub releases. The separate playstore branch keeps
/// its own version and excludes the GitHub update checker entirely.
const kAppVersion = '1.0.7';
const kAppBuildNumber = 3003;
