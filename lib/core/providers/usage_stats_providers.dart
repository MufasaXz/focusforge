import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_catalog.dart';
import '../services/local_store.dart';
import 'app_providers.dart';
import 'shield_providers.dart';
import 'usage_providers.dart';

/// How the usage stats group an app.
enum UsageCategory { distracting, productive, other }

/// Sorts apps into distracting, productive and other, and decides which apps
/// count toward screen time at all.
///
/// An app the user has a Shield rule for is distracting by their own choice.
/// Otherwise a short list of well-known apps decides, then the category the
/// developer declared to Android (games, social, video and news are
/// distracting; productivity is productive). Everything else is "other".
///
/// Only apps that appear in the launcher are counted, so the home screen,
/// the system UI and background services never inflate the total. When the
/// engine cannot list launchable apps, system apps are left out instead.
@immutable
class UsageClassifier {
  const UsageClassifier({
    required this.apps,
    required this.shielded,
    required this.launchable,
    this.overrides = const {},
  });

  final Map<String, InstalledApp> apps;

  /// The user's own choices, which outrank everything else.
  final Map<String, UsageCategory> overrides;
  final Set<String> shielded;
  final Set<String> launchable;

  // ApplicationInfo.CATEGORY_* values.
  static const _game = 0;
  static const _video = 2;
  static const _social = 4;
  static const _news = 5;
  static const _productivity = 7;

  static const _knownDistracting = {
    'com.google.android.youtube',
    'com.instagram.android',
    'com.instagram.barcelona',
    'com.facebook.katana',
    'com.facebook.lite',
    'com.snapchat.android',
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.twitter.android',
    'com.reddit.frontpage',
    'com.pinterest',
    'com.netflix.mediaclient',
    'com.amazon.avod.thirdpartyclient',
    'in.startv.hotstar',
    'com.jio.media.ondemand',
    'tv.twitch.android.app',
    'com.discord',
    'com.mxtech.videoplayer.ad',
    'com.sharechat.app',
    'in.mohalla.sharechat',
    'com.moj.mojapp',
  };

  static const _knownProductive = {
    AppCatalog.selfPackage,
    'com.google.android.apps.docs',
    'com.google.android.apps.docs.editors.docs',
    'com.google.android.apps.docs.editors.sheets',
    'com.google.android.apps.docs.editors.slides',
    'com.google.android.apps.classroom',
    'com.google.android.keep',
    'com.google.android.calendar',
    'com.google.android.apps.tasks',
    'com.microsoft.office.word',
    'com.microsoft.office.excel',
    'com.microsoft.office.powerpoint',
    'com.microsoft.office.onenote',
    'com.microsoft.office.officehubrow',
    'notion.id',
    'com.evernote',
    'com.duolingo',
    'org.khanacademy.android',
    'org.coursera.android',
    'com.udemy.android',
    'com.byjus.thelearningapp',
    'com.unacademyapp',
    'com.quizlet.quizletandroid',
    'com.ichi2.anki',
    'com.microblink.photomath',
    'com.wolfram.android.alpha',
    'com.physicswallah.live',
    'com.google.android.apps.bard',
    'com.openai.chatgpt',
    'com.google.android.apps.youtube.kids',
    'com.vedantu.app',
    'com.adda247.app',
    'com.testbook.tbapp',
    'co.gradeup.android',
    'com.embibe.student',
    'com.allen.digital',
    'com.aakash.app',
    'com.toppr.app',
    'com.doubtnut.app',
    'com.brainly',
    'com.chegg',
    'com.socratic.android',
    'org.edx.mobile',
    'com.memrise.android.memrisecompanion',
    'com.babbel.mobile.android.en',
    'com.goodnotes.android',
    'com.microsoft.teams',
    'us.zoom.videomeetings',
    'com.google.android.apps.meetings',
    'com.adobe.reader',
    'com.google.android.apps.photos.scanner',
    'com.microsoft.office.lens',
    'com.todoist',
    'com.ticktick.task',
    'net.cozic.joplin',
    'md.obsidian',
    'com.forest.android',
  };

  /// Whether [packageId]'s time belongs in the screen-time totals.
  bool counts(String packageId) {
    if (launchable.isNotEmpty) return launchable.contains(packageId);
    final app = apps[packageId];
    return app != null && !app.isSystem;
  }

  UsageCategory categoryOf(String packageId) {
    final chosen = overrides[packageId];
    if (chosen != null) return chosen;
    if (shielded.contains(packageId)) return UsageCategory.distracting;
    if (_knownDistracting.contains(packageId)) return UsageCategory.distracting;
    if (_knownProductive.contains(packageId)) return UsageCategory.productive;
    return switch (apps[packageId]?.category) {
      _game || _video || _social || _news => UsageCategory.distracting,
      _productivity => UsageCategory.productive,
      _ => UsageCategory.other,
    };
  }

  String nameOf(String packageId) => apps[packageId]?.name ?? packageId;

  /// [minutes] narrowed to the apps that count, optionally one category.
  Map<String, int> select(Map<String, int> minutes, [UsageCategory? only]) => {
    for (final entry in minutes.entries)
      if (entry.value > 0 &&
          counts(entry.key) &&
          (only == null || categoryOf(entry.key) == only))
        entry.key: entry.value,
  };

  /// Minutes per category for one day's [minutes].
  Map<UsageCategory, int> split(Map<String, int> minutes) {
    final totals = {for (final c in UsageCategory.values) c: 0};
    for (final entry in select(minutes).entries) {
      final category = categoryOf(entry.key);
      totals[category] = totals[category]! + entry.value;
    }
    return totals;
  }
}

/// The user's own app groups, kept on the phone.
class UsageCategoryOverrides extends Notifier<Map<String, UsageCategory>> {
  @override
  Map<String, UsageCategory> build() {
    final stored = ref
        .read(localStoreProvider)
        .getMap(StoreKeys.usageCategories);
    return {
      for (final entry in (stored ?? const {}).entries)
        for (final category in UsageCategory.values)
          if (category.name == entry.value) entry.key: category,
    };
  }

  /// Sets [packageId]'s group, or returns it to automatic when null.
  Future<void> set(String packageId, UsageCategory? category) async {
    final next = {...state};
    if (category == null) {
      next.remove(packageId);
    } else {
      next[packageId] = category;
    }
    state = next;
    await ref.read(localStoreProvider).setMap(StoreKeys.usageCategories, {
      for (final entry in next.entries) entry.key: entry.value.name,
    });
  }
}

final usageCategoryOverridesProvider =
    NotifierProvider<UsageCategoryOverrides, Map<String, UsageCategory>>(
      UsageCategoryOverrides.new,
    );

final usageClassifierProvider = Provider<UsageClassifier>((ref) {
  final apps = ref.watch(installedAppsProvider).valueOrNull ?? const [];
  return UsageClassifier(
    overrides: ref.watch(usageCategoryOverridesProvider),
    apps: {for (final app in apps) app.packageId: app},
    shielded: {
      for (final entry in ref.watch(whitelistProvider))
        if (entry.packageId != null && entry.tier.isEnforced) entry.packageId!,
    },
    launchable:
        ref.watch(launchablePackagesProvider).valueOrNull ?? const <String>{},
  );
});

/// Midnight at the start of [day].
DateTime dayStart(DateTime day) => DateTime(day.year, day.month, day.day);

/// Midnight [days] calendar days after [day]'s, or before it when negative.
///
/// Counted on the calendar, not in 24-hour steps: a daylight-saving day is 23
/// or 25 hours long, and a fixed step from midnight lands at 23:00 or 01:00,
/// on the wrong date or on the same one again.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// The Monday that starts [day]'s week.
DateTime weekStart(DateTime day) =>
    addDays(day, -(day.weekday - DateTime.monday));

/// Foreground minutes per package for one calendar day, up to now for today.
///
/// Read only after the app-list agreement; empty before it, for days in the
/// future, and for days Android no longer keeps events for.
final dayUsageProvider = FutureProvider.family<Map<String, int>, DateTime>((
  ref,
  day,
) async {
  if (!ref.watch(appListConsentProvider)) return const {};
  final start = dayStart(day);
  final now = DateTime.now();
  if (start.isAfter(now)) {
    // A day not yet begun reads as empty; read it again once it starts, or a
    // week shown before midnight keeps an empty today after it.
    final begins = Timer(start.difference(now), ref.invalidateSelf);
    ref.onDispose(begins.cancel);
    return const {};
  }
  final end = addDays(start, 1);
  return AppCatalog.usageBetween(start, end.isAfter(now) ? now : end);
});

/// Seven days of usage, Monday first, for the week starting [monday].
final weekUsageProvider =
    FutureProvider.family<List<Map<String, int>>, DateTime>((ref, monday) {
      final start = weekStart(monday);
      return Future.wait([
        for (var i = 0; i < 7; i++)
          ref.watch(dayUsageProvider(addDays(start, i)).future),
      ]);
    });

/// Clears cached usage so a refresh, or a return to the screen, reads again.
void refreshUsage(WidgetRef ref) {
  ref.invalidate(dayUsageProvider);
  ref.invalidate(weekUsageProvider);
  ref.invalidate(appUsageTodayProvider);
}
