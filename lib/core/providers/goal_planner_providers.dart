import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/focus_goal.dart';
import '../services/local_store.dart';
import 'app_providers.dart';
import 'study_providers.dart';

/// Calendar changes are state: a date-bound target must expire even when the
/// app stays open overnight. The shell refreshes this on foreground return.
class FocusCalendarDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void refresh() => state = _today();
}

final focusCalendarDateProvider =
    NotifierProvider<FocusCalendarDateNotifier, DateTime>(
      FocusCalendarDateNotifier.new,
    );

class FocusGoalPlannerNotifier extends Notifier<FocusGoalPlanner> {
  static const storageKey = 'goal.planner';

  @override
  FocusGoalPlanner build() => FocusGoalPlanner.fromJson(
    ref.read(localStoreProvider).getMap(storageKey),
  );

  Future<void> save(FocusGoalPlan plan) async {
    final next = state.withPlan(plan);
    // Publish only after storage succeeds so a failed save never changes Home.
    await ref.read(localStoreProvider).setMap(storageKey, next.toJson());
    state = next;
  }
}

final focusGoalPlannerProvider =
    NotifierProvider<FocusGoalPlannerNotifier, FocusGoalPlanner>(
      FocusGoalPlannerNotifier.new,
    );

final activeFocusGoalProvider = Provider<FocusGoalPlan?>((ref) {
  final plan = ref
      .watch(focusGoalPlannerProvider)
      .forDate(ref.watch(focusCalendarDateProvider));
  return plan != null && plan.totalMinutes > 0 ? plan : null;
});

/// Matches launcher-widget and badge attribution on a shared device. Local
/// history is kept on sign-out, but another account cannot earn its minutes.
bool _ownsGoalTime(Ref ref, String owner) {
  final uid = ref.watch(userProvider.select((user) => user.uid));
  final store = ref.read(localStoreProvider);
  final historyOwner =
      store.getString(StoreKeys.achievementHistoryOwner) ?? uid;
  final aliases = store.getMap(StoreKeys.achievementAliases) ?? const {};
  return (owner.isNotEmpty && owner == uid) ||
      aliases[owner] == uid ||
      (owner.isEmpty && historyOwner == uid);
}

/// A period's completed minutes per subject, with the current focus block.
final activeSubjectGoalMinutesProvider = Provider<Map<String, int>>((ref) {
  final plan = ref.watch(activeFocusGoalProvider);
  if (plan == null) return const {};
  final date = ref.watch(focusCalendarDateProvider);
  final from = plan.periodStart(date);
  final until = plan.periodEnd(date);
  final totals = <String, int>{};
  for (final session in ref.watch(sessionsProvider)) {
    if (!session.completed ||
        !_ownsGoalTime(ref, session.ownerUid) ||
        session.startedAt.isBefore(from) ||
        !session.startedAt.isBefore(until)) {
      continue;
    }
    totals.update(
      session.subjectId,
      (value) => value + session.minutes,
      ifAbsent: () => session.minutes,
    );
  }
  final timer = ref.watch(timerProvider);
  final started = timer.segmentStartedAt;
  if (timer.phase == TimerPhase.focus &&
      _ownsGoalTime(ref, timer.segmentOwnerUid ?? ref.read(userProvider).uid) &&
      started != null &&
      !started.isBefore(from) &&
      started.isBefore(until)) {
    final presets = ref.watch(presetsProvider);
    final preset = presets[timer.presetIndex.clamp(0, presets.length - 1)];
    final elapsed =
        (preset.focusDuration + timer.segmentExtra - timer.remaining).inMinutes;
    if (elapsed > 0) {
      totals.update(
        timer.subjectId ?? '',
        (value) => value + elapsed,
        ifAbsent: () => elapsed,
      );
    }
  }
  return Map.unmodifiable(totals);
});

final activeFocusGoalSecondsProvider = Provider<int>((ref) {
  final plan = ref.watch(activeFocusGoalProvider);
  if (plan == null) {
    return 0;
  }
  final date = ref.watch(focusCalendarDateProvider);
  final from = plan.periodStart(date);
  final until = plan.periodEnd(date);
  final banked = ref
      .watch(sessionsProvider)
      .where(
        (s) =>
            s.completed &&
            _ownsGoalTime(ref, s.ownerUid) &&
            !s.startedAt.isBefore(from) &&
            s.startedAt.isBefore(until),
      )
      .fold<int>(0, (sum, s) => sum + s.minutes * 60);
  final timer = ref.watch(timerProvider);
  final started = timer.segmentStartedAt;
  if (timer.phase != TimerPhase.focus ||
      !_ownsGoalTime(
        ref,
        timer.segmentOwnerUid ?? ref.read(userProvider).uid,
      ) ||
      started == null ||
      started.isBefore(from) ||
      !started.isBefore(until)) {
    return banked;
  }
  final presets = ref.watch(presetsProvider);
  final preset = presets[timer.presetIndex.clamp(0, presets.length - 1)];
  final elapsed = preset.focusDuration + timer.segmentExtra - timer.remaining;
  return banked + (elapsed.isNegative ? 0 : elapsed.inSeconds);
});

final activeFocusGoalProgressProvider = Provider<double>((ref) {
  final plan = ref.watch(activeFocusGoalProvider);
  if (plan == null) {
    return 0;
  }
  return (ref.watch(activeFocusGoalSecondsProvider) / (plan.totalMinutes * 60))
      .clamp(0.0, 1.0);
});
