/// Duration formatting helpers shared across screens.
String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// `24:59` style clock for the focus timer.
String formatClock(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  if (hours > 0) {
    return '$hours:${minutes.padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

String formatHours(double hours) {
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// "48h", "12.5h", "0.4h" — hours to one decimal, without a pointless trailing
/// zero.
///
/// Every hour value that reaches the screen goes through here, because
/// interpolating a `double` straight into a string is how a chart label ends up
/// reading "0.4166666666666667h" and wrapping out of its bubble.
String formatHoursShort(double hours) => hours == hours.roundToDouble()
    ? '${hours.toInt()}h'
    : '${hours.toStringAsFixed(1)}h';

/// The spoken form of [formatHoursShort], for semantics labels and tooltips:
/// "2 hours", "1 hour", "0.4 hours".
String spokenHours(double hours) {
  if (hours == hours.roundToDouble()) {
    final n = hours.toInt();
    return '$n ${n == 1 ? 'hour' : 'hours'}';
  }
  return '${hours.toStringAsFixed(1)} hours';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String formatDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Persona greeting that tracks the clock.
String greetingFor(DateTime d) {
  final h = d.hour;
  if (h < 5) return 'Still up';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
