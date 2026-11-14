import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/local_store.dart';
import 'brain/reminders.dart';
import 'brain/timetable.dart';

/// What Pip remembers between launches. Kept on the phone only.
@immutable
class AssistantMemory {
  const AssistantMemory({
    this.examId,
    this.examDate,
    this.lastSeen,
    this.lastTipAt,
    this.introduced = false,
    this.quiet = false,
    this.aiConsent,
    this.remindersOff = false,
    this.examReminders = false,
    this.timetable,
    this.tipTurn = 0,
    this.helloTurn = 0,
    this.lastSaid,
    this.homeReminderOn,
    this.lastRank,
    this.reminders = const [],
  });

  /// The exam the user is preparing for, from the exam guide.
  final String? examId;
  final DateTime? examDate;

  /// When the user last had Pip on screen, for "welcome back".
  final DateTime? lastSeen;

  /// When Pip last offered a greeting or thought on Home. Speech is rare on
  /// purpose: a character that keeps talking becomes something to dismiss.
  final DateTime? lastTipAt;

  /// Whether Pip has introduced itself in the chat.
  final bool introduced;

  /// Whether Pip keeps its tips to itself on the home screen.
  final bool quiet;

  /// Whether the user agreed to online answers: null until asked.
  final bool? aiConsent;

  /// Whether the user turned Pip's evening reminders off.
  final bool remindersOff;

  /// Whether the user asked Pip to count down to the exam: notifications a
  /// month, two weeks, a week, three days and a day before, and on the day.
  final bool examReminders;

  /// The daily timetable Pip made with the user, if any.
  final Timetable? timetable;

  /// How many tips Pip has offered, so its thoughts take turns.
  final int tipTurn;

  /// How many hellos Pip has said, so its greetings take turns too.
  final int helloTurn;

  /// The line Pip said last on the home screen, by its source key, so the
  /// next thing it says is never the same one again.
  final String? lastSaid;

  /// The day Pip last showed a due reminder on Home, so it says it once.
  final DateTime? homeReminderOn;

  /// The leaderboard place Pip last saw, so it can cheer a climb once.
  final int? lastRank;

  /// Reminders the user set by date: tests, exams and tasks.
  final List<StudyReminder> reminders;

  AssistantMemory copyWith({
    String? examId,
    DateTime? examDate,
    DateTime? lastSeen,
    DateTime? lastTipAt,
    bool? introduced,
    bool? quiet,
    bool? aiConsent,
    bool? remindersOff,
    bool? examReminders,
    Timetable? timetable,
    bool clearTimetable = false,
    int? tipTurn,
    int? helloTurn,
    String? lastSaid,
    DateTime? homeReminderOn,
    int? lastRank,
    List<StudyReminder>? reminders,
  }) => AssistantMemory(
    examId: examId ?? this.examId,
    examDate: examDate ?? this.examDate,
    lastSeen: lastSeen ?? this.lastSeen,
    lastTipAt: lastTipAt ?? this.lastTipAt,
    introduced: introduced ?? this.introduced,
    quiet: quiet ?? this.quiet,
    aiConsent: aiConsent ?? this.aiConsent,
    remindersOff: remindersOff ?? this.remindersOff,
    examReminders: examReminders ?? this.examReminders,
    timetable: clearTimetable ? null : (timetable ?? this.timetable),
    tipTurn: tipTurn ?? this.tipTurn,
    helloTurn: helloTurn ?? this.helloTurn,
    lastSaid: lastSaid ?? this.lastSaid,
    homeReminderOn: homeReminderOn ?? this.homeReminderOn,
    lastRank: lastRank ?? this.lastRank,
    reminders: reminders ?? this.reminders,
  );

  Map<String, dynamic> toJson() => {
    'examId': ?examId,
    'examDate': ?examDate?.toIso8601String(),
    'lastSeen': ?lastSeen?.millisecondsSinceEpoch,
    'lastTipAt': ?lastTipAt?.millisecondsSinceEpoch,
    'introduced': introduced,
    'quiet': quiet,
    'aiConsent': ?aiConsent,
    'remindersOff': remindersOff,
    'examReminders': examReminders,
    'timetable': ?timetable?.toJson(),
    'tipTurn': tipTurn,
    'helloTurn': helloTurn,
    'lastSaid': ?lastSaid,
    'homeReminderOn': ?homeReminderOn?.toIso8601String(),
    'lastRank': ?lastRank,
    'reminders': [for (final r in reminders) r.toJson()],
  };

  /// Reads a stored map, ignoring any field of the wrong type.
  factory AssistantMemory.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AssistantMemory();
    final date = json['examDate'];
    final seen = json['lastSeen'];
    final tip = json['lastTipAt'];
    final shown = json['homeReminderOn'];
    return AssistantMemory(
      examId: json['examId'] is String ? json['examId'] as String : null,
      examDate: date is String ? DateTime.tryParse(date) : null,
      lastSeen: seen is int ? DateTime.fromMillisecondsSinceEpoch(seen) : null,
      lastTipAt: tip is int ? DateTime.fromMillisecondsSinceEpoch(tip) : null,
      introduced: json['introduced'] == true,
      quiet: json['quiet'] == true,
      aiConsent: json['aiConsent'] is bool ? json['aiConsent'] as bool : null,
      remindersOff: json['remindersOff'] == true,
      examReminders: json['examReminders'] == true,
      timetable: Timetable.fromJson(json['timetable']),
      tipTurn: json['tipTurn'] is int ? json['tipTurn'] as int : 0,
      helloTurn: json['helloTurn'] is int ? json['helloTurn'] as int : 0,
      lastSaid: json['lastSaid'] is String ? json['lastSaid'] as String : null,
      homeReminderOn: shown is String ? DateTime.tryParse(shown) : null,
      lastRank: json['lastRank'] is int ? json['lastRank'] as int : null,
      reminders: [
        if (json['reminders'] case final List list)
          for (final item in list) ?StudyReminder.fromJson(item),
      ],
    );
  }
}

class AssistantMemoryNotifier extends Notifier<AssistantMemory> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  AssistantMemory build() {
    final saved = AssistantMemory.fromJson(_store.getMap(StoreKeys.assistant));
    // Preserve existing choices when upgrading. The active-account mirror is
    // replaced on account switch, so one student's choice cannot enable
    // cloud processing for another student on a shared device.
    return saved.copyWith(
      aiConsent: _store.getBool('pip_cloud_consent') ?? saved.aiConsent,
    );
  }

  Future<void> _save(AssistantMemory next) async {
    state = next;
    if (next.aiConsent case final allowed?) {
      await _store.setBool('pip_cloud_consent', allowed);
    } else {
      await _store.remove('pip_cloud_consent');
    }
    await _store.setMap(StoreKeys.assistant, next.toJson());
  }

  /// Moves Pip's memory from account [from] to account [to] on this device.
  ///
  /// What Pip knows (chat consent, exam, timetable, reminders) belongs to an
  /// account. The outgoing account's memory is kept for it, and the incoming
  /// one gets its own back, or starts empty.
  Future<void> switchAccount(String from, String to) async {
    if (from == to) return;
    if (from.isNotEmpty) {
      await _store.setMap(_accountKey(from), state.toJson());
    }
    final saved = _store.getMap(_accountKey(to));
    await _store.remove(_accountKey(to));
    await _save(AssistantMemory.fromJson(saved));
  }

  static String _accountKey(String uid) => 'assistant.account.$uid';

  Future<void> setExam(String id) => _save(state.copyWith(examId: id));

  Future<void> setExamDate(DateTime date) => _save(
    state.copyWith(examDate: DateTime(date.year, date.month, date.day)),
  );

  Future<void> markSeen(DateTime at) => _save(state.copyWith(lastSeen: at));

  /// Pip said hello with the line [said].
  Future<void> markHello(String said) =>
      _save(state.copyWith(helloTurn: state.helloTurn + 1, lastSaid: said));

  /// Pip offered an unsolicited Home greeting or thought [said] at [at].
  Future<void> markTipShown(DateTime at, String said) => _save(
    state.copyWith(lastTipAt: at, tipTurn: state.tipTurn + 1, lastSaid: said),
  );

  Future<void> markIntroduced() => _save(state.copyWith(introduced: true));

  Future<void> setQuiet(bool quiet) => _save(state.copyWith(quiet: quiet));

  Future<void> setAiConsent(bool allowed) =>
      _save(state.copyWith(aiConsent: allowed));

  Future<void> setRemindersOff(bool off) =>
      _save(state.copyWith(remindersOff: off));

  Future<void> setExamReminders(bool on) =>
      _save(state.copyWith(examReminders: on));

  Future<void> setTimetable(Timetable? timetable) => _save(
    state.copyWith(timetable: timetable, clearTimetable: timetable == null),
  );

  Future<void> setLastRank(int rank) => _save(state.copyWith(lastRank: rank));

  /// Most reminders kept at once; the oldest goes first.
  static const maxReminders = 20;

  Future<StudyReminder> addReminder({
    required String title,
    required DateTime at,
    required bool exam,
  }) async {
    final reminder = StudyReminder(
      id: ReminderRequest.nextId(state.reminders),
      title: title,
      at: at,
      exam: exam,
    );
    final kept = [...state.reminders, reminder]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _save(
      state.copyWith(
        reminders: kept.length > maxReminders
            ? kept.sublist(kept.length - maxReminders)
            : kept,
      ),
    );
    return reminder;
  }

  Future<void> removeReminder(int id) => _save(
    state.copyWith(
      reminders: [
        for (final r in state.reminders)
          if (r.id != id) r,
      ],
    ),
  );

  /// Drops reminders whose day has passed.
  Future<void> pruneReminders(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final live = [
      for (final r in state.reminders)
        if (!r.day.isBefore(today)) r,
    ];
    if (live.length != state.reminders.length) {
      await _save(state.copyWith(reminders: live));
    }
  }

  Future<void> markHomeReminder(DateTime day) => _save(
    state.copyWith(homeReminderOn: DateTime(day.year, day.month, day.day)),
  );
}

final assistantMemoryProvider =
    NotifierProvider<AssistantMemoryNotifier, AssistantMemory>(
      AssistantMemoryNotifier.new,
    );

/// Whether Pip has already greeted the user since the app started.
///
/// In memory only: a new launch is a new hello, and a return to the Home tab
/// within one session is not.
final assistantGreetedProvider = StateProvider<bool>((ref) => false);
