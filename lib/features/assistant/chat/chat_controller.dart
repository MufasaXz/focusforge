import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/focus_goal.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../assistant_memory.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/study_snapshot.dart';

enum ChatStatus { idle, thinking, typing }

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
  });

  final int id;
  final bool fromPip;
  final Copy? copy;

  /// What the user typed, shown exactly as typed.
  final String? text;
  final ChatCard? card;
}

@immutable
class ChatState {
  const ChatState({
    this.entries = const [],
    this.status = ChatStatus.idle,
    this.step,
    this.suggestions = const [],
    this.lastActive,
    this.goTo,
    this.savedPlans = const {},
  });

  final List<ChatEntry> entries;
  final ChatStatus status;

  /// What Pip is working out, while it thinks.
  final Copy? step;
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
    List<Suggestion>? suggestions,
    DateTime? lastActive,
    ChatDestination? goTo,
    bool clearGoTo = false,
    Set<int>? savedPlans,
  }) => ChatState(
    entries: entries ?? this.entries,
    status: status ?? this.status,
    step: clearStep ? null : (step ?? this.step),
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

  /// Shorter pauses when the system asks for less motion.
  bool fast = false;

  @override
  ChatState build() => const ChatState();

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
    await run(brain.parse(said));
  }

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
      default:
        break;
    }

    final steps = brain.thinkingFor(action.act);
    for (final step in steps) {
      if (generation != _generation) return;
      state = state.copyWith(status: ChatStatus.thinking, step: step);
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
        ChatEntry(id: _ids++, fromPip: true, copy: item.copy, card: item.card),
      );
      await _pause(fast ? 30 : 140);
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

  /// Saves the exam date the user picked, then counts down to it.
  Future<void> setExamDate(DateTime date) async {
    await ref.read(assistantMemoryProvider.notifier).setExamDate(date);
    await run(const AssistantAction(Act.examDate));
  }

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
    final length = item.copy?.key.length ?? 24;
    return (360 + length * 12).clamp(420, 1400);
  }

  Future<void> _pause(int milliseconds) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
