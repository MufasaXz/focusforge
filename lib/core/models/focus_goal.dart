import 'package:flutter/foundation.dart';

// The week tag is retained only to recognize unsupported legacy callers/data.
enum FocusGoalScope { day, week }

/// A daily target with optional, exact subject allocations.
/// Repeated targets run through Sunday; progress always belongs to one day.
@immutable
class FocusGoalPlan {
  FocusGoalPlan({
    required this.scope,
    required DateTime date,
    required this.totalMinutes,
    required Map<String, int> subjectMinutes,
    this.repeatThisWeek = false,
  }) : date = DateTime(date.year, date.month, date.day),
       subjectMinutes = Map.unmodifiable(subjectMinutes) {
    if (totalMinutes < 0 ||
        totalMinutes > maxMinutes ||
        subjectMinutes.entries.any((e) => e.key.isEmpty || e.value < 0) ||
        (subjectMinutes.values.any((value) => value > 0) &&
            subjectMinutes.values.fold<int>(0, (sum, value) => sum + value) !=
                totalMinutes)) {
      throw ArgumentError('Subject time must add up to the selected target.');
    }
  }

  static const maxMinutes = 12 * 60;
  final FocusGoalScope scope;
  final DateTime date;
  final int totalMinutes;
  final Map<String, int> subjectMinutes;
  final bool repeatThisWeek;

  bool appliesOn(DateTime day) {
    final current = DateTime(day.year, day.month, day.day);
    final end = DateTime(
      date.year,
      date.month,
      date.day + (repeatThisWeek ? DateTime.sunday - date.weekday : 0),
    );
    return scope == FocusGoalScope.day &&
        !current.isBefore(date) &&
        !current.isAfter(end);
  }

  DateTime periodStart(DateTime day) => DateTime(day.year, day.month, day.day);

  DateTime periodEnd(DateTime day) {
    final start = periodStart(day);
    return DateTime(start.year, start.month, start.day + 1);
  }

  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'date': date.toIso8601String(),
    'totalMinutes': totalMinutes,
    'subjectMinutes': subjectMinutes,
    'repeatThisWeek': repeatThisWeek,
  };

  static FocusGoalPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final scope = switch (raw['scope']) {
      'day' => FocusGoalScope.day,
      _ => null,
    };
    final dateRaw = raw['date'];
    final date = dateRaw is String ? DateTime.tryParse(dateRaw) : null;
    final total = raw['totalMinutes'];
    final allocations = raw['subjectMinutes'];
    if (scope == null || date == null || total is! int || allocations is! Map) {
      return null;
    }
    final values = <String, int>{};
    for (final entry in allocations.entries) {
      if (entry.key is! String || entry.value is! int) return null;
      values[entry.key as String] = entry.value as int;
    }
    try {
      return FocusGoalPlan(
        scope: scope,
        date: date,
        totalMinutes: total,
        subjectMinutes: values,
        repeatThisWeek: raw['repeatThisWeek'] == true,
      );
    } on ArgumentError {
      return null;
    }
  }
}

@immutable
class FocusGoalPlanner {
  const FocusGoalPlanner({this.day, this.week});
  final FocusGoalPlan? day;

  /// Compatibility slot for old callers. Never loaded, saved, or activated.
  final FocusGoalPlan? week;

  FocusGoalPlan? forDate(DateTime date) {
    if (day?.appliesOn(date) ?? false) return day;
    return null;
  }

  FocusGoalPlanner withPlan(FocusGoalPlan plan) {
    if (plan.scope != FocusGoalScope.day) {
      throw ArgumentError('Focus goals apply to one day.');
    }
    return FocusGoalPlanner(day: plan);
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    if (day != null) 'day': day!.toJson(),
  };

  factory FocusGoalPlanner.fromJson(Map<String, dynamic>? json) =>
      FocusGoalPlanner(day: FocusGoalPlan.fromJson(json?['day']));
}
