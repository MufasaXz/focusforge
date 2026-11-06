import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/local_store.dart';

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
  });

  /// The exam the user is preparing for, from the exam guide.
  final String? examId;
  final DateTime? examDate;

  /// When the user last had Pip on screen, for "welcome back".
  final DateTime? lastSeen;

  /// When Pip last offered a tip on the home screen. Tips are rare on
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

  AssistantMemory copyWith({
    String? examId,
    DateTime? examDate,
    DateTime? lastSeen,
    DateTime? lastTipAt,
    bool? introduced,
    bool? quiet,
    bool? aiConsent,
    bool? remindersOff,
  }) => AssistantMemory(
    examId: examId ?? this.examId,
    examDate: examDate ?? this.examDate,
    lastSeen: lastSeen ?? this.lastSeen,
    lastTipAt: lastTipAt ?? this.lastTipAt,
    introduced: introduced ?? this.introduced,
    quiet: quiet ?? this.quiet,
    aiConsent: aiConsent ?? this.aiConsent,
    remindersOff: remindersOff ?? this.remindersOff,
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
  };

  /// Reads a stored map, ignoring any field of the wrong type.
  factory AssistantMemory.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AssistantMemory();
    final date = json['examDate'];
    final seen = json['lastSeen'];
    final tip = json['lastTipAt'];
    return AssistantMemory(
      examId: json['examId'] is String ? json['examId'] as String : null,
      examDate: date is String ? DateTime.tryParse(date) : null,
      lastSeen: seen is int ? DateTime.fromMillisecondsSinceEpoch(seen) : null,
      lastTipAt: tip is int ? DateTime.fromMillisecondsSinceEpoch(tip) : null,
      introduced: json['introduced'] == true,
      quiet: json['quiet'] == true,
      aiConsent: json['aiConsent'] is bool ? json['aiConsent'] as bool : null,
      remindersOff: json['remindersOff'] == true,
    );
  }
}

class AssistantMemoryNotifier extends Notifier<AssistantMemory> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  AssistantMemory build() =>
      AssistantMemory.fromJson(_store.getMap(StoreKeys.assistant));

  Future<void> _save(AssistantMemory next) {
    state = next;
    return _store.setMap(StoreKeys.assistant, next.toJson());
  }

  Future<void> setExam(String id) => _save(state.copyWith(examId: id));

  Future<void> setExamDate(DateTime date) => _save(
    state.copyWith(examDate: DateTime(date.year, date.month, date.day)),
  );

  Future<void> markSeen(DateTime at) => _save(state.copyWith(lastSeen: at));

  Future<void> markTipShown(DateTime at) =>
      _save(state.copyWith(lastTipAt: at));

  Future<void> markIntroduced() => _save(state.copyWith(introduced: true));

  Future<void> setQuiet(bool quiet) => _save(state.copyWith(quiet: quiet));

  Future<void> setAiConsent(bool allowed) =>
      _save(state.copyWith(aiConsent: allowed));

  Future<void> setRemindersOff(bool off) =>
      _save(state.copyWith(remindersOff: off));
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
