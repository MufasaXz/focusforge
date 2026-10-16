import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'translations.dart';

/// Bundled display copy. Locale follows the phone; no preference is persisted.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  static const supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('bn'),
    Locale('ur'),
    Locale('ta'),
    Locale('te'),
    Locale('mr'),
    Locale('gu'),
    Locale('es'),
    Locale('pt'),
    Locale('fr'),
    Locale('de'),
    Locale('it'),
    Locale('tr'),
    Locale('ru'),
    Locale('uk'),
    Locale('ar'),
    Locale('fa'),
    Locale('id'),
    Locale('ms'),
    Locale('vi'),
    Locale('th'),
    Locale('ko'),
    Locale('ja'),
    Locale('zh'),
  ];
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    _AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static Locale resolve(Iterable<Locale> preferences) {
    for (final requested in preferences) {
      for (final supported in supportedLocales) {
        if (supported.languageCode == requested.languageCode) return supported;
      }
    }
    return const Locale('en');
  }

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      AppStrings(resolve(ui.PlatformDispatcher.instance.locales));

  /// Replace slots in one pass so user-entered text is never reinterpreted.
  String text(String source, [List<Object?> values = const []]) {
    final translated = translations[locale.languageCode]?[source] ?? source;
    return translated.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < values.length
          ? (values[index]?.toString() ?? '')
          : match[0]!;
    });
  }
}

extension AppStringContext on BuildContext {
  String tr(String source, [List<Object?> values = const []]) =>
      AppStrings.of(this).text(source, values);
}

/// Copy created outside widgets uses the same ordered phone locales.
String tr(String source, [List<Object?> values = const []]) =>
    AppStrings(AppStrings.resolve(ui.PlatformDispatcher.instance.locales))
        .text(source, values);

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
