import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/focus_goal.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/services/ai_backend_service.dart';
import '../../../core/services/local_store.dart';
import '../assistant_memory.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/study_snapshot.dart';
import '../brain/reminders.dart';
import '../brain/timetable.dart';
import '../nudges/pip_nudges.dart';

enum ChatStatus { idle, thinking, typing }

/// An online answer as plain chat text.
///
/// The model sometimes writes Markdown, and a bubble shows text exactly as it
/// is, so headings and bold lose their marks, list items become bullets, and
/// runs of blank lines close up.
String tidyAnswer(String reply) {
  final lines = [
    for (final line in reply.replaceAll('\r\n', '\n').split('\n'))
      line
          .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
          .replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ')
          .replaceAll(RegExp(r'\*\*|__|`'), '')
          .trimRight(),
  ];
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Where the chat wants to send the user next, once it has spoken.
enum ChatDestination { focus, shield }

/// One line in the conversation.
@immutable
class ChatEntry {
  const ChatEntry({
    required this.id,
    required this.fromPip,
    this.copy,
    this.text,
    this.card,
    this.online = false,
    this.at,
  });

  final int id;
  final bool fromPip;
  final Copy? copy;

  /// What the user typed, shown exactly as typed.
  final String? text;
  final ChatCard? card;

  /// Whether Pip's line came from the online model.
  final bool online;

  /// When the line was added, so only new lines animate in.
  final DateTime? at;
}

@immutable
class ChatState {
  const ChatState({
    this.entries = const [],
    this.status = ChatStatus.idle,
    this.step,
    this.trail = const [],
    this.suggestions = const [],
    this.lastActive,
    this.goTo,
    this.savedPlans = const {},
  });

  final List<ChatEntry> entries;
  final ChatStatus status;

  /// What Pip is working out, while it thinks.
  final Copy? step;

  /// The steps already done in this think, oldest first.
  final List<Copy> trail;
  final List<Suggestion> suggestions;
  final DateTime? lastActive;
  final ChatDestination? goTo;

  /// Plan cards already saved as today's goal, by entry id.
  final Set<int> savedPlans;

  bool get busy => status != ChatStatus.idle;

  ChatState copyWith({
    List<ChatEntry>? entries,
    ChatStatus? status,
    Copy? step,
    bool clearStep = false,
    List<Copy>? trail,
    List<Suggestion>? suggestions,
    DateTime? lastActive,
    ChatDestination? goTo,
    bool clearGoTo = false,
    Set<int>? savedPlans,
  }) => ChatState(
    entries: entries ?? this.entries,
    status: status ?? this.status,
    step: clearStep ? null : (step ?? this.step),
    trail: clearStep ? const [] : (trail ?? this.trail),
    suggestions: suggestions ?? this.suggestions,
    lastActive: lastActive ?? this.lastActive,
    goTo: clearGoTo ? null : (goTo ?? this.goTo),
    savedPlans: savedPlans ?? this.savedPlans,
  );
}

/// The conversation with Pip, kept for as long as the app runs.
///
/// Replies arrive the way a person types them: a short think for anything
/// that reads the user's data, then each line after a pause sized to its
/// length. A newer request cancels an older one mid-reply, so two answers
/// never interleave.
class ChatController extends Notifier<ChatState> {
  static const brain = AssistantBrain();

  int _ids = 0;
  int _generation = 0;
  int _turn = 0;

  /// A question held while the user answers the online-answers question.
  String? _pending;

  /// Whether this conversation has already suggested signing in.
  bool _suggestedSignIn = false;

  /// Whether the user asked for exam reminders before Pip knew the date.
  bool _pendingExamReminder = false;

  /// A reminder the user named before saying when it is.
  ReminderRequest? _pendingReminder;

  /// Shorter pauses when the system asks for less motion.
  bool fast = false;

  @override
  ChatState build() {
    // A reset (another account, or deletion) rebuilds this same instance.
    // Whatever was still on its way belongs to the old conversation: moving
    // the generation on stops it, and the half-asked questions go with it.
    _generation++;
    _pending = null;
    _suggestedSignIn = false;
    _pendingExamReminder = false;
    _pendingReminder = null;
    return const ChatState();
  }

  /// Called when the chat screen opens, with the request that opened it.
  Future<void> open({AssistantAction? action}) async {
    if (action != null) return run(action);
    final last = state.lastActive;
    final stale =
        last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 20);
    if (state.entries.isEmpty || stale) {
      final introduced = ref.read(assistantMemoryProvider).introduced;
      await run(AssistantAction(introduced ? Act.greet : Act.intro));
    }
  }

  Future<void> send(String text) async {
    final said = text.trim();
    if (said.isEmpty) return;
    _add(ChatEntry(id: _ids++, fromPip: false, text: said));
    final local = brain.parse(said);
    if (!brain.wantsOnline(said, local)) return run(local);

    // Online answers need a signed-in account, the backend and the user's
    // say-so. Without any of them the phone answers, as it always can.
    final consent = ref.read(assistantMemoryProvider).aiConsent;
    if (consent == false) return run(local);
    final backend = ref.read(aiBackendProvider);
    if (ref.read(accountUidProvider) == null) {
      if (!_suggestedSignIn) {
        _suggestedSignIn = true;
        await say(AssistantReply([Say(brain.aiNote(AiFailure.signedOut))]));
      }
      return run(local);
    }
    if (backend == null) return run(local);
    if (consent == null) {
      _pending = said;
      return say(brain.aiConsentAsk());
    }
    if (!_claimOnlineAnswer()) return _outOfEnergy(local);
    return _askOnline(said, local, backend);
  }

  /// Asks the online model, then falls back to the phone if it cannot.
  Future<void> _askOnline(
    String said,
    AssistantAction local,
    AiBackend backend,
  ) async {
    final generation = ++_generation;
    final history = _history();
    const reading = Copy('Reading your sessions…');
    state = state.copyWith(
      suggestions: const [],
      status: ChatStatus.thinking,
      step: reading,
      trail: const [],
    );
    final snapshot = await StudySnapshot.gather(ref.read);
    await _pause(fast ? 60 : 380);
    if (generation != _generation) return;
    // Consent can be withdrawn, or the account signed out, while the study
    // summary is read: nothing leaves the phone unless both still hold now.
    if (ref.read(assistantMemoryProvider).aiConsent != true ||
        ref.read(accountUidProvider) == null) {
      state = state.copyWith(status: ChatStatus.idle, clearStep: true);
      return run(local);
    }
    state = state.copyWith(step: const Copy('Thinking…'), trail: [reading]);
    try {
      final reply = await backend.askAiAssistant(
        userMessage: said,
        extraContext: brain.aiContext(snapshot),
        history: history,
        locale: _locale().languageCode,
        allowed: () =>
            generation == _generation &&
            ref.read(assistantMemoryProvider).aiConsent == true &&
            ref.read(accountUidProvider) != null,
      );
      if (generation != _generation) return;
      await say(
        AssistantReply([
          Say(Copy.raw(tidyAnswer(reply)), online: true),
        ], suggestions: brain.defaults(snapshot)),
        generation: generation,
      );
    } on AiBackendException catch (error) {
      if (generation != _generation) return;
      if (error.failure == AiFailure.withdrawn) {
        // Turned off before sending: the phone answers, with nothing to say
        // about the online brain.
        state = state.copyWith(status: ChatStatus.idle, clearStep: true);
        return run(local);
      }
      final phoneAnswers =
          brain.fallsBackLocally(error.failure) && local.act != Act.unknown;
      await say(
        AssistantReply([
          Say(brain.aiNote(error.failure)),
        ], suggestions: phoneAnswers ? const [] : brain.defaults(snapshot)),
        generation: generation,
      );
      if (phoneAnswers && generation == _generation) await run(local);
    }
  }

  /// Online answers each user gets a day, counted on the phone. The phone's
  /// own answers have no limit.
  static const onlineAnswersPerDay = 5;

  /// Takes one of today's online answers, or false when they are used up.
  bool _claimOnlineAnswer() {
    final store = ref.read(localStoreProvider);
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    final day = store.getMap(StoreKeys.assistantAiDay);
    final used = day?['day'] == today && day?['count'] is int
        ? day!['count'] as int
        : 0;
    if (used >= onlineAnswersPerDay) return false;
    unawaited(
      store.setMap(StoreKeys.assistantAiDay, {
        'day': today,
        'count': used + 1,
        if (day?['day'] == today && day?['told'] == true) 'told': true,
      }),
    );
    return true;
  }

  /// Says once a day that the online answers are used up, then answers on
  /// the phone as usual.
  Future<void> _outOfEnergy(AssistantAction local) async {
    final store = ref.read(localStoreProvider);
    final day = {...?store.getMap(StoreKeys.assistantAiDay)};
    if (day['told'] != true) {
      day['told'] = true;
      unawaited(store.setMap(StoreKeys.assistantAiDay, day));
      await say(
        const AssistantReply([
          Say(
            Copy(
              'Daily Pip energy used up! Focus on your study block and come back tomorrow.',
            ),
          ),
        ]),
      );
    }
    if (local.act != Act.unknown) return run(local);
  }

  /// Sends a report of Pip's online answer in entry [entryId] for review,
  /// and keeps a copy on the phone. True once the report is on its way.
  Future<bool> report(int entryId, String reason) async {
    final entries = state.entries;
    final index = entries.indexWhere((e) => e.id == entryId);
    if (index < 0) return false;
    final strings = AppStrings(_locale());
    final reply = entries[index].copy?.resolve(strings) ?? '';
    final question = entries
        .take(index)
        .lastWhere((e) => !e.fromPip, orElse: () => entries[index])
        .text;
    final store = ref.read(localStoreProvider);
    final kept = store.getMap(StoreKeys.assistantReports)?['items'];
    await store.setMap(StoreKeys.assistantReports, {
      'items': [
        // The most recent 50, this one included.
        if (kept is List) ...kept.skip(kept.length > 49 ? kept.length - 49 : 0),
        {
          'reason': reason,
          'reply': reply,
          'question': ?question,
          'at': DateTime.now().toIso8601String(),
        },
      ],
    });
    // Only a report that reached the review service counts as sent; the
    // copy on the phone is no review.
    final backend = ref.read(aiBackendProvider);
    if (backend == null) return false;
    try {
      await backend.reportReply(
        reply: reply,
        reason: reason,
        question: question,
      );
      return true;
    } on AiBackendException {
      return false;
    }
  }

  /// The last few lines of the conversation, oldest first, without the
  /// message being asked now.
  ///
  /// Only the user's own words and Pip's online answers go: Pip's answers
  /// from the phone can carry the user's name, or other people's from the
  /// leaderboard, and the consent promises never to send a name.
  List<Map<String, String>> _history() {
    final strings = AppStrings(_locale());
    final lines = state.entries.toList();
    if (lines.isNotEmpty && !lines.last.fromPip) lines.removeLast();
    final turns = <Map<String, String>>[
      for (final entry in lines)
        if (entry.card == null && (!entry.fromPip || entry.online))
          if ((entry.text ?? entry.copy?.resolve(strings)) case final text?
              when text.trim().isNotEmpty)
            {'role': entry.fromPip ? 'pip' : 'user', 'text': text},
    ];
    return turns.length > 8 ? turns.sublist(turns.length - 8) : turns;
  }

  static ui.Locale _locale() =>
      AppStrings.resolve(ui.PlatformDispatcher.instance.locales);

  /// Turns online answers on or off from the chat menu.
  Future<void> setOnlineAnswers(bool allowed) =>
      ref.read(assistantMemoryProvider.notifier).setAiConsent(allowed);

  Future<void> choose(Suggestion suggestion) async {
    _add(ChatEntry(id: _ids++, fromPip: false, copy: suggestion.label));
    await run(suggestion.action);
  }

  /// Answers [action]: does what it asks that needs no screen, then replies.
  Future<void> run(AssistantAction action) async {
    final generation = ++_generation;
    state = state.copyWith(suggestions: const []);
    final memory = ref.read(assistantMemoryProvider.notifier);
    switch (action.act) {
      case Act.examPick:
        final id = action.arg;
        if (id != null) await memory.setExam(id);
      case Act.goalSet:
        final minutes = action.value;
        if (minutes != null) await _saveGoal(minutes);
      case Act.intro:
        await memory.markIntroduced();
      case Act.reminder:
        return _setReminder(
          ReminderRequest.parse(action.said ?? '', DateTime.now()),
          generation,
        );
      case Act.reminderOff:
        final asked = ReminderRequest.parse(
          action.said ?? '',
          DateTime.now(),
        ).title.toLowerCase().split(' ').where((w) => w.length >= 3).toSet();
        final match = ref
            .read(assistantMemoryProvider)
            .reminders
            .where((r) => r.title.toLowerCase().split(' ').any(asked.contains))
            .firstOrNull;
        if (match != null) {
          await memory.removeReminder(match.id);
          _syncReminders();
          return say(
            AssistantReply([
              Say(
                Copy('Removed the reminder for {0}.', [Copy.raw(match.title)]),
              ),
            ]),
            generation: generation,
          );
        }
      case Act.timetable when action.arg == 'today':
        final saved = ref.read(assistantMemoryProvider).timetable;
        if (saved != null) return useTimetableToday(saved);
      case Act.timetableOff:
        await memory.setTimetable(null);
        _syncReminders();
      case Act.examReminderOff:
        _pendingExamReminder = false;
        await memory.setExamReminders(false);
        _syncReminders();
      case Act.examReminder:
        final named = action.arg;
        if (named != null) await memory.setExam(named);
        final snapshot = StudySnapshot.capture(ref.read);
        final dated =
            (snapshot.daysToExam ?? -1) >= 0 && snapshot.memory.examId != null;
        _pendingExamReminder = !dated;
        if (dated) {
          await memory.setExamReminders(true);
          final allowed = await _allowNotifications();
          _syncReminders();
          if (generation != _generation) return;
          return _reply(
            AssistantAction(Act.examReminder, value: allowed ? 1 : 0),
            generation,
          );
        }
      case Act.aiAllow:
        await memory.setAiConsent(true);
        final question = _pending;
        _pending = null;
        final backend = ref.read(aiBackendProvider);
        if (question != null && backend != null) {
          return _askOnline(question, brain.parse(question), backend);
        }
      case Act.aiDecline:
        await memory.setAiConsent(false);
        final question = _pending;
        _pending = null;
        await say(
          const AssistantReply([
            Say(
              Copy(
                'Okay, I’ll keep everything on this phone. You can change this from the menu.',
              ),
            ),
          ]),
          generation: generation,
        );
        if (question != null && generation == _generation) {
          return run(brain.parse(question));
        }
        return;
      default:
        break;
    }

    await _reply(action, generation);
  }

  /// Thinks, reads the user's data and answers [action].
  Future<void> _reply(AssistantAction action, int generation) async {
    final steps = brain.thinkingFor(action.act);
    for (final (index, step) in steps.indexed) {
      if (generation != _generation) return;
      state = state.copyWith(
        status: ChatStatus.thinking,
        step: step,
        trail: steps.sublist(0, index),
      );
      await _pause(fast ? 120 : 620);
    }
    if (steps.isEmpty) {
      state = state.copyWith(status: ChatStatus.typing, clearStep: true);
      await _pause(fast ? 60 : 260);
    }

    final snapshot = await StudySnapshot.gather(ref.read);
    if (generation != _generation) return;

    var request = action;
    if (action.act == Act.focusNow && !snapshot.timerRunning) {
      final subject = action.arg ?? brain.subjectForNow(snapshot);
      _startTimer(subject);
      request = AssistantAction(Act.focusNow, arg: subject);
    }
    final reply = brain.respond(request, snapshot, turn: _turn++);
    await say(reply, generation: generation);
    if (action.act == Act.focusNow && generation == _generation) {
      state = state.copyWith(goTo: ChatDestination.focus);
    }
  }

  /// Types out [reply] line by line.
  Future<void> say(AssistantReply reply, {int? generation}) async {
    final current = generation ?? ++_generation;
    for (final item in reply.says) {
      if (current != _generation) return;
      state = state.copyWith(status: ChatStatus.typing, clearStep: true);
      await _pause(_typingMs(item));
      if (current != _generation) return;
      _add(
        ChatEntry(
          id: _ids++,
          fromPip: true,
          copy: item.copy,
          card: item.card,
          online: item.online,
          at: DateTime.now(),
        ),
      );
      // Let the line finish writing itself in before the next one starts.
      await _pause(fast ? 30 : 140 + _writeInMs(item));
    }
    if (current != _generation) return;
    state = state.copyWith(
      status: ChatStatus.idle,
      clearStep: true,
      suggestions: reply.suggestions,
    );
  }

  /// Starts a focus block on [subjectId] from a plan card.
  Future<void> startBlock(String? subjectId) async {
    final snapshot = StudySnapshot.capture(ref.read);
    if (!snapshot.timerRunning) _startTimer(subjectId);
    await say(
      brain.respond(AssistantAction(Act.focusNow, arg: subjectId), snapshot),
    );
    state = state.copyWith(goTo: ChatDestination.focus);
  }

  /// Saves [plan] as today's goal, counting what is already done today.
  Future<void> savePlan(int entryId, PlanCard plan) async {
    final allocation = <String, int>{};
    for (final entry in plan.todayBySubject.entries) {
      if (entry.key.isEmpty) continue;
      allocation.update(
        entry.key,
        (v) => v + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    for (final block in plan.blocks) {
      allocation.update(
        block.subjectId,
        (v) => v + block.minutes,
        ifAbsent: () => block.minutes,
      );
    }
    final untagged = plan.todayBySubject[''] ?? 0;
    final allocated = allocation.values.fold(0, (sum, m) => sum + m);
    final total = (allocated + untagged).clamp(15, FocusGoalPlan.maxMinutes);
    final exact = untagged == 0 && allocated == total;
    await ref
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: ref.read(focusCalendarDateProvider),
            totalMinutes: total,
            subjectMinutes: exact ? allocation : const {},
          ),
        );
    state = state.copyWith(savedPlans: {...state.savedPlans, entryId});
    await say(
      const AssistantReply([
        Say(Copy('Saved. Your goal ring now shows this plan.')),
      ]),
    );
  }

  /// Saves the exam date the user picked, then counts down to it, or sets
  /// the reminders the user asked for before Pip knew the date.
  Future<void> setExamDate(DateTime date) async {
    await ref.read(assistantMemoryProvider.notifier).setExamDate(date);
    _syncReminders();
    await run(
      AssistantAction(_pendingExamReminder ? Act.examReminder : Act.examDate),
    );
  }

  /// Sets [request] if it has a day still ahead, or asks for one.
  Future<void> _setReminder(ReminderRequest request, int generation) async {
    final at = request.at;
    if (at == null || at.isBefore(DateTime.now())) {
      _pendingReminder = request;
      return say(
        brain.reminderNeedsDate(request.title, passed: at != null),
        generation: generation,
      );
    }
    _pendingReminder = null;
    final title = request.title.isEmpty
        ? AppStrings(_locale()).text('Study reminder')
        : request.title;
    final reminder = await ref
        .read(assistantMemoryProvider.notifier)
        .addReminder(title: title, at: at, exam: request.exam);
    final allowed = await _allowNotifications();
    _syncReminders();
    if (generation != _generation) return;
    await say(
      brain.reminderSet(
        reminder,
        notifications: allowed,
        hasTime: request.hasTime,
      ),
      generation: generation,
    );
  }

  /// The day the user picked for the reminder Pip asked about.
  Future<void> setReminderDate(DateTime date) {
    final pending =
        _pendingReminder ?? const ReminderRequest(title: '', exam: false);
    final (hour, minute) = pending.time ?? (18, 0);
    return _setReminder(
      ReminderRequest(
        title: pending.title,
        exam: pending.exam,
        at: DateTime(date.year, date.month, date.day, hour, minute),
        time: pending.time,
      ),
      ++_generation,
    );
  }

  /// Removes a reminder from the reminders card.
  Future<void> deleteReminder(int id) async {
    await ref.read(assistantMemoryProvider.notifier).removeReminder(id);
    _syncReminders();
  }

  /// Saves [timetable] from the card in entry [entryId], and its daily
  /// reminder if the user wants one.
  Future<void> saveTimetable(int entryId, Timetable timetable) async {
    await ref.read(assistantMemoryProvider.notifier).setTimetable(timetable);
    final allowed = timetable.remind && await _allowNotifications();
    _syncReminders();
    state = state.copyWith(savedPlans: {...state.savedPlans, entryId});
    final start = Clock(timetable.effectiveStart);
    await say(
      AssistantReply(
        [
          Say(
            !timetable.remind
                ? const Copy('Saved. Ask me any time to change it.')
                : allowed
                ? Copy('Saved. I’ll remind you just before {0} each day.', [
                    start,
                  ])
                : Copy(
                    'Saved. Notifications are off for FocusForge, so I’ll remind you on Home at {0} instead.',
                    [start],
                  ),
          ),
        ],
        suggestions: [
          Suggestion(
            const Copy('Use it as today’s focus plan'),
            Icons.playlist_add_check_rounded,
            AssistantAction(Act.timetable, arg: 'today'),
          ),
        ],
      ),
    );
  }

  /// Turns [timetable] into today's focus plan: a custom plan with its block
  /// length on the timer, and today's goal split by its subjects.
  Future<void> useTimetableToday(Timetable timetable) async {
    final strings = AppStrings(_locale());
    final total = timetable.totalMinutes.clamp(15, FocusGoalPlan.maxMinutes);
    await ref
        .read(planLibraryProvider.notifier)
        .save(
          CustomPlan(
            id: timetablePlanId,
            name: strings.text('Pip’s timetable'),
            goalMinutes: total,
            focusMinutes: timetable.blockMinutes,
          ),
        );
    final timer = ref.read(timerProvider.notifier);
    final running = ref.read(timerProvider).running;
    if (!running) {
      final index = ref
          .read(presetsProvider)
          .indexWhere((preset) => preset.key == timetablePlanId);
      if (index >= 0) await timer.setPreset(index);
      final first = timetable.slots.firstOrNull?.subjectId ?? '';
      if (first.isNotEmpty) timer.setSubject(first);
    }
    final tagged = {
      for (final MapEntry(key: id, value: minutes)
          in timetable.subjectMinutes.entries)
        if (id.isNotEmpty) id: minutes,
    };
    final exact = tagged.values.fold(0, (a, b) => a + b) == total;
    await ref
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: ref.read(focusCalendarDateProvider),
            totalMinutes: total,
            subjectMinutes: exact ? tagged : const {},
          ),
        );
    await say(
      AssistantReply(
        [
          Say(
            Copy(
              'Done. Today’s focus plan follows your timetable: {0} in {1} blocks, and your goal ring shows each subject.',
              [Minutes(total), Minutes(timetable.blockMinutes)],
            ),
          ),
        ],
        suggestions: const [
          Suggestion(
            Copy('Start a block'),
            Icons.play_arrow_rounded,
            AssistantAction(Act.focusNow),
          ),
        ],
      ),
    );
  }

  /// The plan library id of the plan made from Pip's timetable.
  static const timetablePlanId = 'pip-timetable';

  Future<bool> _allowNotifications() =>
      ref.read(pipNotificationAccessProvider).request();

  /// Hands the reminders to the phone without holding up the reply.
  void _syncReminders() =>
      unawaited(PipNudges.sync(ref.read, AppStrings(_locale())));

  void clearGoTo() => state = state.copyWith(clearGoTo: true);

  void clear() {
    _generation++;
    state = const ChatState();
  }

  void _startTimer(String? subjectId) {
    final timer = ref.read(timerProvider.notifier);
    if (ref.read(timerProvider).phase.isBreak) timer.skip();
    if (subjectId != null) timer.setSubject(subjectId);
    timer.start();
  }

  Future<void> _saveGoal(int minutes) => ref
      .read(focusGoalPlannerProvider.notifier)
      .save(
        FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: ref.read(focusCalendarDateProvider),
          totalMinutes: minutes.clamp(15, FocusGoalPlan.maxMinutes),
          subjectMinutes: const {},
        ),
      );

  void _add(ChatEntry entry) {
    state = state.copyWith(
      entries: [...state.entries, entry],
      lastActive: DateTime.now(),
      status: entry.fromPip ? ChatStatus.idle : state.status,
    );
  }

  int _typingMs(Say item) {
    if (fast) return 90;
    if (item.card != null) return 650;
    // Online answers were already waited for; the line writes itself in.
    if (item.online) return 320;
    final length = item.copy?.key.length ?? 24;
    return (300 + length * 6).clamp(380, 900);
  }

  /// How long a new line takes to write itself in on screen.
  static int _writeInMs(Say item) {
    final copy = item.copy;
    if (copy == null) return 0;
    return (copy.key.length * 14).clamp(260, 1500);
  }

  Future<void> _pause(int milliseconds) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
