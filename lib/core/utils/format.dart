import 'dart:async';
import 'dart:ui' as ui;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../localization/app_strings.dart';

AppStrings _strings(ui.Locale? locale) => AppStrings(
  locale ?? AppStrings.resolve(ui.PlatformDispatcher.instance.locales),
);

String _number(num value, {int decimals = 0, ui.Locale? locale}) =>
    NumberFormat.decimalPattern(_strings(locale).locale.languageCode).format(
      decimals == 0 ? value : double.parse(value.toStringAsFixed(decimals)),
    );

/// Duration formatting helpers shared across screens. Stored durations stay
/// numeric; visible units and numbers follow the phone or supplied locale.
String formatMinutes(int minutes, {ui.Locale? locale}) {
  final strings = _strings(locale);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return strings.text('{0}m', [_number(m, locale: locale)]);
  if (m == 0) return strings.text('{0}h', [_number(h, locale: locale)]);
  return strings.text('{0}h {1}m', [
    _number(h, locale: locale),
    _number(m, locale: locale),
  ]);
}

/// `24:59` style clock for the focus timer.
String formatClock(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

String formatHours(double hours, {ui.Locale? locale}) =>
    formatMinutes((hours * 60).round(), locale: locale);

/// Hours to one decimal, without a trailing zero.
String formatHoursShort(double hours, {ui.Locale? locale}) =>
    _strings(locale)
        .text('{0}h', [_number(hours, decimals: 1, locale: locale)]);

/// A coarse age for activity history. A future timestamp reads as just now.
String formatRelativeTime(DateTime at, {DateTime? now, ui.Locale? locale}) {
  final strings = _strings(locale);
  final delta = (now ?? DateTime.now()).difference(at);
  if (delta.inMinutes < 1) return strings.text('just now');
  if (delta.inMinutes < 60) {
    return strings.text('{0} min ago', [
      _number(delta.inMinutes, locale: locale),
    ]);
  }
  if (delta.inHours < 24) {
    return strings.text('{0} h ago', [_number(delta.inHours, locale: locale)]);
  }
  if (delta.inDays == 1) return strings.text('Yesterday');
  return strings.text('{0} days ago', [_number(delta.inDays, locale: locale)]);
}

/// Spoken duration for semantics labels and tooltips.
String spokenHours(double hours, {ui.Locale? locale}) => hours == 1
    ? _strings(locale).text('{0} hour', [_number(1, locale: locale)])
    : _strings(locale)
          .text('{0} hours', [_number(hours, decimals: 1, locale: locale)]);

bool _dateDataReady = false;

void _ensureDateData() {
  if (!_dateDataReady) {
    // Registration is synchronous; the future only reports completion.
    unawaited(initializeDateFormatting());
    _dateDataReady = true;
  }
}

String formatDate(DateTime date, {ui.Locale? locale}) {
  _ensureDateData();
  return DateFormat.MMMMEEEEd(_strings(locale).locale.languageCode)
      .format(date);
}

String formatWeekday(DateTime date, {ui.Locale? locale}) {
  _ensureDateData();
  return DateFormat.EEEE(_strings(locale).locale.languageCode).format(date);
}

String formatShortDate(DateTime date, {ui.Locale? locale}) {
  _ensureDateData();
  return DateFormat.yMMMd(_strings(locale).locale.languageCode).format(date);
}

/// Greeting that tracks the local clock and the phone language.
String greetingFor(DateTime date, {ui.Locale? locale}) {
  final strings = _strings(locale);
  if (date.hour < 5) return strings.text('Still up');
  if (date.hour < 12) return strings.text('Good morning');
  if (date.hour < 17) return strings.text('Good afternoon');
  return strings.text('Good evening');
}
