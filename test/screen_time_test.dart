// Screen time: the sum behind the dashboard's "today" figure.
//
// WHAT INVARIANT: foreground time is the span between an app being resumed and
// the matching pause, one app at a time; the screen going off, the lock screen
// or another app coming to the front ends it; a session still open is counted
// up to the moment it is asked about; time is clipped to the window; and the
// apps' minutes add up to the window's own rounded total.
//
// WHY IT MATTERS: this was read from `queryAndAggregateUsageStats`, which
// answers with the system's own daily bucket — written as the day goes on, and
// therefore missing the session the user is in while they are looking at the
// number. The figure looked stuck and lagged the phone. The arithmetic is pure
// and is tested here rather than through the platform channel, because the
// arithmetic is what was wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:usage_stats/usage_stats.dart';

import 'package:focusforge/core/services/app_catalog.dart';

void main() {
  final midnight = DateTime(2026, 10, 7);

  DateTime at(int minutes, [int seconds = 0]) =>
      midnight.add(Duration(minutes: minutes, seconds: seconds));

  EventUsageInfo event(
    String? packageId,
    int type,
    DateTime when, [
    String? activity,
  ]) => EventUsageInfo(
    packageName: packageId,
    className: activity,
    eventType: '$type',
    timeStamp: '${when.millisecondsSinceEpoch}',
  );

  const resumed = 1;
  const paused = 2;
  const stopped = 23;
  const screenOff = 16;
  const keyguardShown = 17;

  Map<String, int> sum(
    List<EventUsageInfo> events,
    DateTime until, {
    DateTime? from,
  }) => AppCatalog.foregroundMinutes(events, until: until, from: from);

  test('a resume and its pause are the app\'s time', () {
    final usage = sum([
      event('com.example.reader', resumed, at(10)),
      event('com.example.reader', paused, at(40)),
    ], at(60));

    expect(usage['com.example.reader'], 30);
  });

  test('a session still open is counted up to now', () {
    final usage = sum([event('com.example.reader', resumed, at(20))], at(35));

    expect(
      usage['com.example.reader'],
      15,
      reason: 'the session in progress is the one the old read always missed',
    );
  });

  test('a second activity in the same app does not end the session', () {
    // Opening a video inside a feed: the feed pauses, the player resumes.
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      event('com.example.reader', resumed, at(5)),
      event('com.example.reader', paused, at(10)),
      event('com.example.reader', paused, at(30)),
    ], at(30));

    expect(
      usage['com.example.reader'],
      30,
      reason: 'the app was in the foreground the whole time',
    );
  });

  test('a stop closes a session that never paused', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      event('com.example.reader', stopped, at(12)),
    ], at(60));

    expect(usage['com.example.reader'], 12);
  });

  test('a stop after a pause does not count the time twice', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      event('com.example.reader', paused, at(12)),
      event('com.example.reader', stopped, at(12)),
    ], at(60));

    expect(usage['com.example.reader'], 12);
  });

  test('a pause with no resume is ignored', () {
    final usage = sum([event('com.example.reader', paused, at(10))], at(60));

    expect(usage, isEmpty, reason: 'there was no session to end');
  });

  test('apps are summed apart, and a whole day survives', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      event('com.example.reader', paused, at(30)),
      event('com.example.player', resumed, at(32)),
      event('com.example.player', paused, at(38)),
      event('com.example.player', resumed, at(40)),
    ], at(70));

    expect(usage['com.example.reader'], 30);
    expect(
      usage['com.example.player'],
      36,
      reason: '6 minutes before the pause, 30 after it, still open',
    );
  });

  test('another app coming to the front ends a session with no pause', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      // The reader never reports its pause.
      event('com.example.player', resumed, at(10)),
    ], at(30));

    expect(usage['com.example.reader'], 10, reason: 'only one app is in front');
    expect(usage['com.example.player'], 20);
  });

  test('the screen going off or locking ends the session', () {
    final off = sum([
      event('com.example.reader', resumed, at(0)),
      event(null, screenOff, at(20)),
    ], at(60));
    expect(off['com.example.reader'], 20);

    final locked = sum([
      event('com.example.reader', resumed, at(0)),
      event(null, keyguardShown, at(15)),
    ], at(60));
    expect(locked['com.example.reader'], 15);
  });

  test('an app open before the window counts only inside it', () {
    final usage = sum(
      [
        event('com.example.reader', resumed, at(-40)),
        event('com.example.reader', paused, at(25)),
      ],
      at(60),
      from: midnight,
    );

    expect(
      usage['com.example.reader'],
      25,
      reason: 'the 40 minutes before midnight belong to yesterday',
    );
  });

  test('a late stop from an earlier screen does not end the current one', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0), 'Feed'),
      event('com.example.reader', paused, at(5), 'Feed'),
      event('com.example.reader', resumed, at(5), 'Player'),
      event('com.example.reader', stopped, at(6), 'Feed'),
      event('com.example.reader', paused, at(30), 'Player'),
    ], at(60));

    expect(usage['com.example.reader'], 30);
  });

  test('a screen resumed twice still ends at its one pause', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0), 'Feed'),
      event('com.example.reader', resumed, at(5), 'Feed'),
      event('com.example.reader', paused, at(10), 'Feed'),
    ], at(60));

    expect(usage['com.example.reader'], 10);
  });

  test('the apps add up to the window\'s own rounded total', () {
    // Three apps of 40 seconds each: two minutes in all. Rounding each app on
    // its own would have reported three.
    final usage = sum([
      event('com.example.a', resumed, at(0)),
      event('com.example.a', paused, at(0, 40)),
      event('com.example.b', resumed, at(1)),
      event('com.example.b', paused, at(1, 40)),
      event('com.example.c', resumed, at(2)),
      event('com.example.c', paused, at(2, 40)),
    ], at(5));

    expect(usage.values.fold(0, (a, b) => a + b), 2);
  });

  test('a short session still reaches the map', () {
    final usage = sum([
      event('com.example.reader', resumed, at(0)),
      event('com.example.reader', paused, at(0, 40)),
    ], at(1));

    expect(
      usage.containsKey('com.example.reader'),
      isTrue,
      reason: 'the card\'s empty state has to mean "nothing was opened"',
    );
    expect(usage['com.example.reader'], 1, reason: 'rounded to the minute');
  });

  test('events with no package or no timestamp are skipped', () {
    final usage = sum([
      EventUsageInfo(
        eventType: '$resumed',
        timeStamp: '${at(0).millisecondsSinceEpoch}',
      ),
      EventUsageInfo(packageName: 'com.example.reader', eventType: '$resumed'),
      EventUsageInfo(
        packageName: '',
        eventType: '$resumed',
        timeStamp: '${at(0).millisecondsSinceEpoch}',
      ),
      EventUsageInfo(
        packageName: 'com.example.reader',
        timeStamp: '${at(0).millisecondsSinceEpoch}',
      ),
      event('com.example.reader', resumed, at(5)),
      event('com.example.reader', paused, at(15)),
    ], at(20));

    expect(usage, {'com.example.reader': 10});
  });

  test('an unreadable event type is skipped rather than guessed', () {
    final usage = sum([
      EventUsageInfo(
        packageName: 'com.example.reader',
        eventType: 'not a number',
        timeStamp: '${at(0).millisecondsSinceEpoch}',
      ),
      event('com.example.reader', resumed, at(5)),
      event('com.example.reader', paused, at(15)),
    ], at(20));

    expect(usage, {'com.example.reader': 10});
  });
}
