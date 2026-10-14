import 'package:flutter/foundation.dart';

enum FocusGoalScope { day, week }

/// A target and an exact allocation of its minutes across study subjects.
/// Daily targets expire at midnight; weekly plans repeat on Monday.
@immutable
class FocusGoalPlan {
  FocusGoalPlan({
    required this.scope,
    required DateTime date,
    required this.totalMinutes,
    required Map<String, int> subjectMinutes,
  }) : date = DateTime(date.year, date.month, date.day),
       subjectMinutes = Map.unmodifiable(subjectMinutes) {
    if (totalMinutes < 0 ||
        totalMinutes > maxMinutes ||
        subjectMinutes.entries.any((e) => e.key.isEmpty || e.value < 0) ||
        subjectMinutes.values.fold<int>(0, (sum, value) => sum + value) !=
            totalMinutes) {
      throw ArgumentError('Subject time must add up to the selected target.');
    }
  }

  static const maxMinutes = 12 * 60;
  final FocusGoalScope scope;
  final DateTime date;
  final int totalMinutes;
  final Map<String, int> subjectMinutes;

  bool appliesOn(DateTime day) {
    final current = DateTime(day.year, day.month, day.day);
    return scope == FocusGoalScope.day
        ? current == date
        : !current.isBefore(periodStart(date));
  }

  DateTime periodStart(DateTime day) => scope == FocusGoalScope.day
      ? date
      : DateTime(day.year, day.month, day.day - day.weekday + 1);

  DateTime periodEnd(DateTime day) {
    final start = periodStart(day);
    return DateTime(
      start.year,
      start.month,
      start.day + (scope == FocusGoalScope.day ? 1 : 7),
    );
  }

  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'date': date.toIso8601String(),
    'totalMinutes': totalMinutes,
    'subjectMinutes': subjectMinutes,
  };

  static FocusGoalPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final scope = switch (raw['scope']) {
      'day' => FocusGoalScope.day,
      'week' => FocusGoalScope.week,
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
  final FocusGoalPlan? week;

  FocusGoalPlan? forDate(DateTime date) {
    if (day?.appliesOn(date) ?? false) return day;
    return week?.appliesOn(date) ?? false ? week : null;
  }

  FocusGoalPlanner withPlan(FocusGoalPlan plan) => FocusGoalPlanner(
    // Explicitly choosing a weekly plan makes it effective immediately. A
    // daily plan saved afterwards can still override that one day.
    day: plan.scope == FocusGoalScope.day ? plan : null,
    week: plan.scope == FocusGoalScope.week ? plan : week,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    if (day != null) 'day': day!.toJson(),
    if (week != null) 'week': week!.toJson(),
  };

  factory FocusGoalPlanner.fromJson(Map<String, dynamic>? json) =>
      FocusGoalPlanner(
        day: FocusGoalPlan.fromJson(json?['day']),
        week: FocusGoalPlan.fromJson(json?['week']),
      );
}
