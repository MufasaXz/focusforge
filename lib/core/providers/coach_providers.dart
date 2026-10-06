import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The widgets the first-run tips point at.
///
/// The tips used to be placed at fixed fractions of the screen, which meant
/// they drifted the moment anything above them changed height — and the one
/// pointing at the navigation bar landed below the dashboard's own bounds, so
/// it highlighted nothing at all. A key measures the real widget instead, and
/// the shell and the dashboard can both reach the same registry because it
/// lives in a provider rather than in either of them.
class CoachTargets {
  CoachTargets();

  /// The daily progress ring on the dashboard.
  final GlobalKey ring = GlobalKey(debugLabel: 'coach.ring');

  /// The streak chip in the dashboard greeting.
  final GlobalKey streak = GlobalKey(debugLabel: 'coach.streak');

  /// The call to action inside the dashboard's first-run empty state.
  final GlobalKey emptyCta = GlobalKey(debugLabel: 'coach.emptyCta');

  /// The Focus destination in the navigation bar.
  ///
  /// It lives in the shell rather than the dashboard, which is exactly why the
  /// tips had to move to the root overlay: the nav bar is a sibling of the tab
  /// body, so a spotlight drawn inside the dashboard could never reach it.
  final GlobalKey focusTab = GlobalKey(debugLabel: 'coach.focusTab');
}

final coachTargetsProvider = Provider<CoachTargets>(
  (ref) => CoachTargets(),
);
