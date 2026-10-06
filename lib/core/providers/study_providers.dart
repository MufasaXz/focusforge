import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/local_store.dart';
import 'app_providers.dart';

// -- Subjects ----------------------------------------------------------------

class SubjectsNotifier extends Notifier<List<Subject>> {
  /// Subject metadata — name, icon, colour, weekly target — with whatever
  /// counters happened to be attached. Counters are not state: they are
  /// recomputed from the session log on every [build], which is what keeps the
  /// breakdown from disagreeing with the ring above it, and from carrying
  /// yesterday's minutes into today.
  List<Subject> _base = SeedData.subjects;

  @override
  List<Subject> build() =>
      _withDerivedCounters(_base, ref.watch(sessionsProvider));

  LocalStore get _store => ref.read(localStoreProvider);

  /// Restores the stored catalogue.
  ///
  /// Null means no key was ever written — a first run — so the seed catalogue
  /// is kept deliberately. A non-null list is authoritative even when empty:
  /// [LocalStore.getList] returns the same empty list for a missing key as for
  /// a stored `[]`, so bootstrap resolves the ambiguity before calling here.
  /// A user who removed every subject, or deleted their account, must not have
  /// the seed come back on the next launch.
  void hydrate(List<Map<String, dynamic>>? stored) {
    if (stored == null) return;
    _base = stored.map(Subject.fromJson).toList(growable: false);
    state = _withDerivedCounters(_base, ref.read(sessionsProvider));
  }

  Future<void> _persist() => _store.setList(
    StoreKeys.subjects,
    _base.map((s) => s.toJson()).toList(growable: false),
  );

  Future<void> add(Subject subject) async {
    _base = [..._base, subject];
    state = _withDerivedCounters(_base, ref.read(sessionsProvider));
    await _persist();
  }

  Future<void> remove(String id) async {
    _base = _base.where((s) => s.id != id).toList(growable: false);
    state = _withDerivedCounters(_base, ref.read(sessionsProvider));
    await _persist();
  }

  Future<void> setWeeklyTarget(String id, double hours) async {
    _base = [
      for (final s in _base)
        if (s.id == id) s.copyWith(weekTarget: hours) else s,
    ];
    state = _withDerivedCounters(_base, ref.read(sessionsProvider));
    await _persist();
  }
}

/// Recomputes today's and this week's minutes for every subject from the
/// session log.
///
/// Deriving beats accumulating: the ring, the weekly chart and the heatmap
/// already read the log, so a counter incremented separately can drift from
/// them — and, because nothing resets it, it *does* drift the moment the clock
/// passes midnight. The week is Monday-aligned, matching the heatmap, so
/// "this week" means the same span everywhere the app says it.
List<Subject> _withDerivedCounters(
  List<Subject> subjects,
  List<FocusSession> sessions,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

  int minutesSince(String id, DateTime from) => sessions
      .where(
        (s) => s.completed && s.subjectId == id && !s.startedAt.isBefore(from),
      )
      .fold(0, (sum, s) => sum + s.minutes);

  return [
    for (final s in subjects)
      s.copyWith(
        minutesToday: minutesSince(s.id, today),
        weekDone: minutesSince(s.id, monday) / 60,
      ),
  ];
}

final subjectsProvider = NotifierProvider<SubjectsNotifier, List<Subject>>(
  SubjectsNotifier.new,
);

// -- Sessions ----------------------------------------------------------------

class SessionsNotifier extends Notifier<List<FocusSession>> {
  @override
  List<FocusSession> build() => const [];

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(List<Map<String, dynamic>> stored) {
    state = stored.map(FocusSession.fromJson).toList(growable: false);
  }

  Future<void> _persist() => _store.setList(
    StoreKeys.sessions,
    state.map((s) => s.toJson()).toList(growable: false),
  );

  /// Appends [session] and returns whether it was added.
  ///
  /// Session ids are deterministic (`s-<segment start>`), so an id already in
  /// the log is a replay: the process died after a recovered block was logged
  /// but before the timer snapshot was cleared, and the next launch recovered
  /// the same block again. Rejecting the duplicate keeps it counted exactly
  /// once — the original entry still holds the focus time, so nothing is lost.
  Future<bool> record(FocusSession session) async {
    if (state.any((s) => s.id == session.id)) return false;
    state = [...state, session];
    await _persist();
    return true;
  }

  List<FocusSession> forDay(DateTime day) => state
      .where(
        (s) =>
            s.startedAt.year == day.year &&
            s.startedAt.month == day.month &&
            s.startedAt.day == day.day,
      )
      .toList(growable: false);

  int minutesToday() =>
      forDay(DateTime.now())
          .where((s) => s.completed)
          .fold(0, (sum, s) => sum + s.minutes);
}

final sessionsProvider = NotifierProvider<SessionsNotifier, List<FocusSession>>(
  SessionsNotifier.new,
);

/// Minutes of completed focus logged today. Drives the dashboard ring.
///
/// Watches the session *state*, not the notifier: watching a notifier rebuilds
/// only when the notifier object itself is replaced, so reading the count
/// through it left the ring at its launch-time value until something else
/// forced a rebuild.
final focusMinutesTodayProvider = Provider<int>(
  (ref) => _minutesOn(ref.watch(sessionsProvider), DateTime.now()),
);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Minutes of completed focus on a given calendar day.
int _minutesOn(List<FocusSession> sessions, DateTime day) => sessions
    .where((s) => s.completed && _sameDay(s.startedAt, day))
    .fold(0, (sum, s) => sum + s.minutes);

/// The last seven days as bar-chart data, oldest first with today last.
///
/// Derived from the session log rather than stored, so the chart can never
/// disagree with the ring above it — both read the same source of truth.
final weeklyBarsProvider = Provider<List<DayBar>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final today = _dateOnly(DateTime.now());
  return List.generate(7, (i) {
    final day = DateTime(today.year, today.month, today.day - (6 - i));
    return DayBar(
      _weekdayLetter(day.weekday),
      _minutesOn(sessions, day) / 60,
      isToday: i == 6,
    );
  });
});

/// Total hours across [weeklyBarsProvider], for the "N h focused" headline.
final weekTotalHoursProvider = Provider<double>(
  (ref) => ref.watch(weeklyBarsProvider).fold(0.0, (sum, d) => sum + d.hours),
);

/// Average hours across the days that actually have time on them.
///
/// Dividing by seven would make a strong week look weak just because the user
/// rests at weekends; the average is meant to describe a *working* day.
final weekAverageHoursProvider = Provider<double>((ref) {
  final bars = ref.watch(weeklyBarsProvider);
  final active = bars.where((d) => d.hours > 0).length;
  if (active == 0) return 0;
  return bars.fold<double>(0, (sum, d) => sum + d.hours) / active;
});

/// Five weeks of dated cells ending with the current week, Monday-first.
///
/// The grid is aligned to real weeks so the weekday columns mean something,
/// which is also why cells later in the current week read as empty rather than
/// being omitted — the shape of the month should not shift as the week fills.
final heatmapWeeksProvider = Provider<List<List<HeatCell>>>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final today = _dateOnly(DateTime.now());
  final thisMonday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  final start = DateTime(
    thisMonday.year,
    thisMonday.month,
    thisMonday.day - 28,
  );

  return List.generate(5, (row) {
    return List.generate(7, (col) {
      final date = DateTime(start.year, start.month, start.day + row * 7 + col);
      final future = date.isAfter(today);
      return HeatCell(
        date: date,
        hours: future ? 0 : _minutesOn(sessions, date) / 60,
      );
    });
  });
});

String _weekdayLetter(int weekday) =>
    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];

// -- Timer -------------------------------------------------------------------

enum TimerPhase {
  focus('Focus', 0),
  shortBreak('Short break', 1),
  longBreak('Long break', 2);

  const TimerPhase(this.label, this.index0);

  final String label;
  final int index0;

  bool get isBreak => this != TimerPhase.focus;
}

/// Everything the Focus screen renders. Immutable so `ref.watch` comparisons
/// stay cheap.
class TimerState {
  const TimerState({
    this.phase = TimerPhase.focus,
    this.running = false,
    this.remaining = const Duration(minutes: 25),
    this.targetEnd,
    this.completedFocusSegments = 0,
    this.presetIndex = 0,
    this.subjectId,
    this.segmentStartedAt,
  });

  final TimerPhase phase;
  final bool running;
  final Duration remaining;

  /// Wall-clock instant the current segment ends.
  ///
  /// This — not a decrementing counter — is the source of truth. A backgrounded
  /// isolate stops firing timers, so a tick-counting clock silently loses time;
  /// comparing against a stored instant means the timer is still correct after
  /// the app has been asleep for an hour.
  final DateTime? targetEnd;

  final int completedFocusSegments;
  final int presetIndex;
  final String? subjectId;

  /// When the current focus segment began, so a completed block can be logged
  /// with a real start time.
  final DateTime? segmentStartedAt;

  bool get idle => !running && remaining == _presetDurationOf(phase);

  TimerState copyWith({
    TimerPhase? phase,
    bool? running,
    Duration? remaining,
    DateTime? targetEnd,
    bool clearTargetEnd = false,
    int? completedFocusSegments,
    int? presetIndex,
    String? subjectId,
    bool clearSubject = false,
    DateTime? segmentStartedAt,
  }) => TimerState(
    phase: phase ?? this.phase,
    running: running ?? this.running,
    remaining: remaining ?? this.remaining,
    targetEnd: clearTargetEnd ? null : (targetEnd ?? this.targetEnd),
    completedFocusSegments:
        completedFocusSegments ?? this.completedFocusSegments,
    presetIndex: presetIndex ?? this.presetIndex,
    // A null argument cannot mean "clear" — every other field reads null as
    // "keep" — so clearing needs its own flag, exactly like [clearTargetEnd].
    subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
    segmentStartedAt: segmentStartedAt ?? this.segmentStartedAt,
  );

  static Duration _presetDurationOf(TimerPhase p) => p == TimerPhase.focus
      ? const Duration(minutes: 25)
      : const Duration(minutes: 5);

  /// 0..1 through the current segment, for the ring.
  double progressFor(PomodoroPreset preset) {
    final total = switch (phase) {
      TimerPhase.focus => preset.focusDuration,
      TimerPhase.shortBreak => preset.shortBreakDuration,
      TimerPhase.longBreak => preset.longBreakDuration,
    };
    if (total.inMilliseconds == 0) return 0;
    return (1 - remaining.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }
}

/// The Pomodoro engine.
///
/// Two rules keep this honest:
///   1. [TimerState.targetEnd] is authoritative — ticks only recompute the
///      display, they never accumulate.
///   2. Every tick re-reads the wall clock, so a suspended isolate, a dropped
///      frame or a slow rebuild cannot cause drift.
class TimerNotifier extends Notifier<TimerState> {
  Timer? _ticker;

  /// Fires when a focus segment completes, so the UI can celebrate.
  final _completions = StreamController<int>.broadcast();

  Stream<int> get completions => _completions.stream;

  /// A block recovered from a run that died mid-segment, held back until the
  /// session log has been hydrated — see [_logRecovered].
  FocusSession? _pendingRecovery;

  /// Whether this notifier has been torn down.
  ///
  /// Riverpod 3 exposes `ref.mounted`; Riverpod 2 does not, so the flag is
  /// maintained by hand. [_logRecovered] defers through a microtask, and a
  /// provider that was invalidated in the meantime would otherwise read a
  /// store it no longer belongs to.
  bool _disposed = false;

  @override
  TimerState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
      _completions.close();
    });
    // Bootstrap hydrates the session log in the same synchronous pass as this
    // notifier, but not necessarily before it. A recovered block must not be
    // recorded into an empty log: `record` persists the in-memory list, so it
    // would replace the stored history with a single entry. Waiting for the
    // log to arrive keeps the recovery honest whatever the wiring order.
    ref.listen(sessionsProvider, (_, next) {
      final pending = _pendingRecovery;
      if (pending == null || next.isEmpty) return;
      _pendingRecovery = null;
      unawaited(_appendRecovered(pending));
    });
    final preset = SeedData.presets[0];
    return TimerState(remaining: preset.focusDuration);
  }

  PomodoroPreset get preset => SeedData.presets[state.presetIndex];

  Duration _durationFor(TimerPhase phase) => switch (phase) {
    TimerPhase.focus => preset.focusDuration,
    TimerPhase.shortBreak => preset.shortBreakDuration,
    TimerPhase.longBreak => preset.longBreakDuration,
  };

  static Duration _durationForPreset(PomodoroPreset preset, TimerPhase phase) =>
      switch (phase) {
        TimerPhase.focus => preset.focusDuration,
        TimerPhase.shortBreak => preset.shortBreakDuration,
        TimerPhase.longBreak => preset.longBreakDuration,
      };

  void _startTicker() {
    _ticker?.cancel();
    // 250ms so the seconds digit never visibly stutters, but the value shown
    // is always derived from the wall clock rather than from tick count.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  /// The last state the timer can be rebuilt from after a cold start.
  ///
  /// [TimerState.targetEnd] is what lets a running segment survive process
  /// death; the rest of the snapshot restores the user's choices (preset,
  /// subject, cycle position) and lets an idle timer come back as it was left.
  /// Ticks are deliberately not persisted — the deadline already encodes them.
  Future<void> _persist() =>
      ref.read(localStoreProvider).setMap(StoreKeys.presets, {
        'presetIndex': state.presetIndex,
        'subjectId': state.subjectId,
        'phase': state.phase.name,
        'running': state.running,
        'targetEnd': state.targetEnd?.millisecondsSinceEpoch,
        'segmentStartedAt': state.segmentStartedAt?.millisecondsSinceEpoch,
        'completedFocusSegments': state.completedFocusSegments,
        'remainingMs': state.remaining.inMilliseconds,
      });

  /// Restores the persisted timer.
  ///
  /// A segment whose deadline is still ahead resumes exactly where it left
  /// off; one whose deadline has passed finished while the process was dead,
  /// so its minutes are written to the session log and the timer lands idle.
  /// Nothing is dropped.
  ///
  /// Call this after `sessionsProvider` has been hydrated where possible —
  /// [build] installs a fallback for when it has not.
  void hydrate(Map<String, dynamic>? stored) {
    if (stored == null) return;

    final presetIndex = _intOr(
      stored['presetIndex'],
      0,
    ).clamp(0, SeedData.presets.length - 1).toInt();
    final preset = SeedData.presets[presetIndex];
    final subjectId = _stringOrNull(stored['subjectId']);
    final segments = _intOr(stored['completedFocusSegments'], 0);
    final phase =
        TimerPhase.values.asNameMap()[stored['phase']] ?? TimerPhase.focus;
    final targetEnd = _dateOrNull(stored['targetEnd']);
    final startedAt = _dateOrNull(stored['segmentStartedAt']);
    final running = stored['running'] == true;
    final pausedMs = _intOr(
      stored['remainingMs'],
      _durationForPreset(preset, phase).inMilliseconds,
    );
    final paused = Duration(milliseconds: pausedMs < 0 ? 0 : pausedMs);

    _ticker?.cancel();
    final now = DateTime.now();

    // The deadline is authoritative: if it has passed, the block completed —
    // even though the app was not alive to watch it finish.
    final finishedWhileAway =
        running && targetEnd != null && !targetEnd.isAfter(now);

    if (finishedWhileAway && phase == TimerPhase.focus) {
      // A running segment's start is recoverable even if the snapshot lost it:
      // it began one focus duration before the deadline.
      final started = startedAt ?? targetEnd.subtract(preset.focusDuration);
      _logRecovered(
        FocusSession(
          id: 's-${started.microsecondsSinceEpoch}',
          subjectId: subjectId ?? '',
          startedAt: started,
          minutes: preset.focus,
        ),
      );
    }

    if (running && targetEnd != null && !finishedWhileAway) {
      state = TimerState(
        phase: phase,
        running: true,
        remaining: targetEnd.difference(now),
        targetEnd: targetEnd,
        completedFocusSegments: segments,
        presetIndex: presetIndex,
        subjectId: subjectId,
        segmentStartedAt: startedAt,
      );
      _startTicker();
      unawaited(_persist());
      return;
    }

    // Idle. A break whose window elapsed while the app was dead has nothing
    // left to give, and a recovered focus block has already been logged, so
    // the next action is a fresh focus block. A paused segment, on the other
    // hand, comes back exactly where it was left.
    state = TimerState(
      presetIndex: presetIndex,
      subjectId: subjectId,
      phase: running ? TimerPhase.focus : phase,
      remaining: running ? preset.focusDuration : paused,
      completedFocusSegments:
          segments + (finishedWhileAway && phase == TimerPhase.focus ? 1 : 0),
      segmentStartedAt: running ? null : startedAt,
    );
    unawaited(_persist());
  }

  /// Writes a block that finished while the app was dead into the session log.
  ///
  /// Deferred by a microtask because bootstrap hydrates every notifier in one
  /// synchronous pass: recording during [hydrate] could land before the log
  /// has loaded, and `record` persists the in-memory list — so it would
  /// replace the stored history with a single entry. The microtask runs after
  /// that pass; if the log still has not arrived, the block waits in
  /// [_pendingRecovery] for the listener installed in [build].
  void _logRecovered(FocusSession session) {
    Future.microtask(() {
      if (_disposed) return;
      final store = ref.read(localStoreProvider);
      final logLoaded =
          ref.read(sessionsProvider).isNotEmpty ||
          store.getList(StoreKeys.sessions).isEmpty;
      if (!logLoaded) {
        _pendingRecovery = session;
        return;
      }
      unawaited(_appendRecovered(session));
    });
  }

  Future<void> _appendRecovered(FocusSession session) async {
    final added = await ref.read(sessionsProvider.notifier).record(session);
    // A replay must not credit the aggregate twice: the block was already
    // counted when it was first logged.
    if (!added) return;
    await ref
        .read(statsProvider.notifier)
        .recordSession(minutes: session.minutes, completed: true);
  }

  void setPreset(int index) {
    if (index < 0 || index >= SeedData.presets.length) return;
    _ticker?.cancel();
    final preset = SeedData.presets[index];
    // Switching pace is not a reason to lose the chosen subject.
    state = TimerState(
      presetIndex: index,
      subjectId: state.subjectId,
      remaining: preset.focusDuration,
    );
    unawaited(_persist());
  }

  void setSubject(String? id) {
    state = state.copyWith(subjectId: id, clearSubject: id == null);
    unawaited(_persist());
  }

  void start() {
    if (state.running) return;
    final now = DateTime.now();
    state = state.copyWith(
      running: true,
      targetEnd: now.add(state.remaining),
      segmentStartedAt: state.phase == TimerPhase.focus
          ? (state.segmentStartedAt ?? now)
          : state.segmentStartedAt,
    );
    _startTicker();
    unawaited(_persist());
  }

  void pause() {
    if (!state.running) return;
    _ticker?.cancel();
    state = state.copyWith(
      running: false,
      remaining: _clampedRemaining(),
      clearTargetEnd: true,
    );
    unawaited(_persist());
  }

  void toggle() => state.running ? pause() : start();

  /// Abandons the current segment and returns to a fresh focus block.
  void reset() {
    _ticker?.cancel();
    state = TimerState(
      presetIndex: state.presetIndex,
      subjectId: state.subjectId,
      completedFocusSegments: state.completedFocusSegments,
      remaining: preset.focusDuration,
    );
    unawaited(_persist());
  }

  /// Jumps to the next phase without logging a session.
  void skip() => _advance(log: false);

  /// Recomputes from the wall clock. Call on resume — a backgrounded app gets
  /// no ticks, so the first frame after waking must resync.
  void sync() {
    if (!state.running) return;
    tick();
  }

  void tick() {
    if (!state.running) return;
    final target = state.targetEnd;
    if (target == null) return;

    final diff = target.difference(DateTime.now());
    if (diff.isNegative || diff == Duration.zero) {
      _advance(log: true);
      return;
    }
    // Only rebuild when the visible second actually changes — the ticker runs
    // at 4Hz but the UI updates at 1Hz.
    if (diff.inSeconds != state.remaining.inSeconds) {
      state = state.copyWith(remaining: diff);
    }
  }

  Duration _clampedRemaining() {
    final target = state.targetEnd;
    if (target == null) return state.remaining;
    final diff = target.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void _advance({required bool log}) {
    final finished = state.phase;
    final wasRunning = state.running;
    _ticker?.cancel();

    if (finished == TimerPhase.focus) {
      final started = state.segmentStartedAt ?? DateTime.now();
      final minutes = preset.focus;
      if (log) {
        _completions.add(minutes);
        // The subject counters are derived from this log, so recording the
        // session is all it takes to credit the subject.
        ref
            .read(sessionsProvider.notifier)
            .record(
              FocusSession(
                id: 's-${started.microsecondsSinceEpoch}',
                subjectId: state.subjectId ?? '',
                startedAt: started,
                minutes: minutes,
              ),
            );
        ref
            .read(statsProvider.notifier)
            .recordSession(minutes: minutes, completed: true);
      }
    }

    final nextSegments = finished == TimerPhase.focus
        ? state.completedFocusSegments + 1
        : state.completedFocusSegments;

    final nextPhase = switch (finished) {
      TimerPhase.focus =>
        nextSegments % preset.segments == 0
            ? TimerPhase.longBreak
            : TimerPhase.shortBreak,
      TimerPhase.shortBreak || TimerPhase.longBreak => TimerPhase.focus,
    };

    final duration = _durationFor(nextPhase);
    state = TimerState(
      phase: nextPhase,
      running: wasRunning,
      remaining: duration,
      targetEnd: wasRunning ? DateTime.now().add(duration) : null,
      completedFocusSegments: nextSegments,
      presetIndex: state.presetIndex,
      subjectId: state.subjectId,
      segmentStartedAt: nextPhase == TimerPhase.focus ? DateTime.now() : null,
    );
    unawaited(_persist());

    if (wasRunning) _startTicker();
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);

// -- Persisted-JSON readers --------------------------------------------------
//
// The timer snapshot is read during bootstrap, so a malformed value must
// degrade to a default rather than throw out of the launch path.

int _intOr(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

String? _stringOrNull(Object? value) => value is String ? value : null;

DateTime? _dateOrNull(Object? value) {
  if (value is! num) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } on ArgumentError {
    // Outside the range DateTime can represent — treat it as unknown.
    return null;
  }
}

// -- Daily goal --------------------------------------------------------------

class DailyGoalNotifier extends Notifier<int> {
  @override
  int build() => SeedData.focusGoalMinutes;

  void hydrate(int? stored) {
    if (stored != null && stored > 0) state = stored;
  }

  Future<void> set(int minutes) async {
    state = minutes;
    await ref.read(localStoreProvider).setInt(StoreKeys.dailyGoal, minutes);
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalNotifier, int>(
  DailyGoalNotifier.new,
);

/// 0..1 progress toward today's goal.
final goalProgressProvider = Provider<double>((ref) {
  final goal = ref.watch(dailyGoalProvider);
  if (goal <= 0) return 0;
  return (ref.watch(focusMinutesTodayProvider) / goal).clamp(0.0, 1.0);
});

// -- Presets -----------------------------------------------------------------

final presetsProvider = Provider<List<PomodoroPreset>>((_) => SeedData.presets);
