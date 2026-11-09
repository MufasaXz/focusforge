import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart' show accountUidProvider;
import '../../../core/services/ai_backend_service.dart'
    show aiBackendProvider, reportReasons;
import '../../../core/models/shield.dart';
import '../../../core/providers/shield_providers.dart';
import '../../../core/services/permission_manager.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_list_disclosure.dart';
import '../../../shared/widgets/expressive_loading_indicator.dart';
import '../../shield/shield_access.dart';
import '../assistant_memory.dart';
import '../brain/assistant_models.dart';
import '../brain/timetable.dart';
import '../home/pip_dock.dart' show TypingDots;
import '../mascot/mascot.dart';
import '../mascot/mascot_life.dart';
import '../mascot/mascot_painter.dart' show MascotColors;
import '../mascot/mascot_rig.dart';
import '../nudges/pip_nudges.dart';
import 'chat_cards.dart';
import 'chat_controller.dart';

/// The conversation with Pip.
///
/// A full screen above the tabs. Pip's head is the profile picture and shows
/// what it is doing — thinking with a pulsing antenna, talking while it types.
/// Every request also has a chip, so nothing here needs typing.
class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key, this.initial});

  /// What to do as soon as the chat opens, such as a tapped tip.
  final AssistantAction? initial;

  @override
  ConsumerState<AssistantChatScreen> createState() =>
      _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _avatar = MascotRig();
  final _hero = MascotRig();
  late final _avatarLife = MascotLife(_avatar);
  late final _heroLife = MascotLife(_hero);

  ChatController get _chat => ref.read(chatProvider.notifier);

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInput);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chat.fast = MediaQuery.disableAnimationsOf(context);
      _avatarLife.start();
      _heroLife.start();
      _hero.wave();
      unawaited(_chat.open(action: widget.initial));
    });
  }

  @override
  void dispose() {
    _input
      ..removeListener(_onInput)
      ..dispose();
    _scroll.dispose();
    _avatarLife.dispose();
    _heroLife.dispose();
    _avatar.dispose();
    _hero.dispose();
    super.dispose();
  }

  DateTime _lastNod = DateTime.fromMillisecondsSinceEpoch(0);

  /// Pip nods now and then while the user types, as if listening.
  void _onInput() {
    setState(() {});
    final now = DateTime.now();
    if (_input.text.trim().isEmpty ||
        now.difference(_lastNod) < const Duration(milliseconds: 2400)) {
      return;
    }
    _lastNod = now;
    _avatar.nod();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        unawaited(
          _scroll.animateTo(
            end,
            duration: Motion.base,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    unawaited(HapticFeedback.selectionClick());
    unawaited(_chat.send(text));
  }

  /// A chip or a card button. Steps that need a permission, a picker or a
  /// tab are handled here; everything else goes to the conversation.
  Future<void> _handle(Suggestion suggestion) async {
    switch (suggestion.action.act) {
      case Act.usageAccess:
        await requestShieldPermission(context, ref, AppPermission.usageAccess);
      case Act.appList:
        final agreed = await confirmAppListAccess(context, ref);
        if (agreed) await _chat.run(const AssistantAction(Act.lock));
      case Act.openShield:
        GoRouter.maybeOf(context)?.go(AppRoutes.paths[AppRoutes.shield]!);
      case Act.openFocus:
        GoRouter.maybeOf(context)?.go(AppRoutes.paths[AppRoutes.focus]!);
      case Act.examDate:
        await _pickExamDate();
      case Act.reminderDate:
        await _pickReminderDate();
      case Act.openLeaderboard:
        GoRouter.maybeOf(context)
            ?.push(AppRoutes.paths[AppRoutes.leaderboard]!);
      default:
        await _chat.choose(suggestion);
    }
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final saved = ref.read(assistantMemoryProvider).examDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: saved != null && !saved.isBefore(today)
          ? saved
          : today.add(const Duration(days: 60)),
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    await _chat.setExamDate(picked);
  }

  /// Asks why the user is reporting Pip's answer in entry [id], then sends it.
  Future<void> _report(int id) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReportDialog(),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final thanks = context.tr('Thanks. This answer will be reviewed.');
    final failed = context.tr(
      'Could not send the report. Check your connection and try again.',
    );
    final sent = await _chat.report(id, reason);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(sent ? thanks : failed)));
  }

  Future<void> _pickReminderDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    await _chat.setReminderDate(picked);
  }

  Future<void> _lock(List<AppMinutes> apps, bool allDay) async {
    if (apps.isEmpty) return;
    final shield = ref.read(whitelistProvider.notifier);
    for (final app in apps) {
      await shield.addInstalledApp(
        packageId: app.packageId,
        name: app.name,
        tier: allDay ? WhitelistTier.blocked : WhitelistTier.focusOnly,
      );
    }
    if (!mounted) return;
    final ready = await ensureShieldAccess(context, ref);
    await _chat.say(
      ChatController.brain.locked(
        [for (final app in apps) app.name],
        allDay: allDay,
        shieldReady: ready,
      ),
    );
  }

  void _go(ChatDestination destination) {
    final route = switch (destination) {
      ChatDestination.focus => AppRoutes.focus,
      ChatDestination.shield => AppRoutes.shield,
    };
    _chat.clearGoTo();
    // Let the last line land before the screen changes.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) GoRouter.maybeOf(context)?.go(AppRoutes.paths[route]!);
    });
  }

  Future<void> _setReminders({required bool off}) async {
    final strings = AppStrings.of(context);
    await ref.read(assistantMemoryProvider.notifier).setRemindersOff(off);
    await PipNudges.sync(ref.read, strings);
  }

  /// Turning online answers on says first what would be sent, as Pip's
  /// own question does; turning them off needs no confirmation.
  Future<void> _changeOnlineAnswers(bool on) async {
    if (!on) return _chat.setOnlineAnswers(false);
    final signedIn = ref.read(accountUidProvider) != null;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Answer with AI when online')),
        content: Text(
          [
            context.tr(
              'Your question, the last few messages and a short study summary go to an AI service. Never your name or email.',
            ),
            if (!signedIn)
              context.tr(
                'Online answers also need a linked account. Until then, answers stay on this phone.',
              ),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Keep it on this phone')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Allow')),
          ),
        ],
      ),
    );
    if (allow == true && mounted) await _chat.setOnlineAnswers(true);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final cs = Theme.of(context).colorScheme;
    ref.listen<ChatState>(chatProvider, (previous, next) {
      if (previous?.entries.length != next.entries.length ||
          previous?.status != next.status ||
          previous?.suggestions.length != next.suggestions.length) {
        _scrollToEnd();
      }
      _avatar.thinking = next.status == ChatStatus.thinking;
      if (next.status == ChatStatus.typing &&
          previous?.status != ChatStatus.typing) {
        _avatar.talk(seconds: 0.8);
      }
      final goTo = next.goTo;
      if (goTo != null && previous?.goTo != goTo) _go(goTo);
    });

    final quiet = ref.watch(assistantMemoryProvider.select((m) => m.quiet));
    final online = ref.watch(
      assistantMemoryProvider.select((m) => m.aiConsent == true),
    );
    // What a question sent now would actually use: consent alone is not
    // enough without a linked account and the service.
    final answersOnline =
        online &&
        ref.watch(accountUidProvider) != null &&
        ref.watch(aiBackendProvider) != null;
    // At rest the header says where answers come from, so it is known
    // before anything is typed.
    final status = switch (chat.status) {
      ChatStatus.thinking => chat.step?.of(context) ?? context.tr('Thinking…'),
      ChatStatus.typing => context.tr('Typing…'),
      ChatStatus.idle =>
        answersOnline
            ? context.tr('Online answers on')
            : context.tr('Answers stay on this phone'),
    };
    final remindersOff = ref.watch(
      assistantMemoryProvider.select((m) => m.remindersOff),
    );
    final entries = chat.entries;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            ExcludeSemantics(
              child: Mascot(rig: _avatar, width: 38, headOnly: true),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(kBuddyName),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.quick,
                    child: Text(
                      status,
                      key: ValueKey(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: chat.busy ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: context.tr('More'),
            onSelected: (value) {
              if (value == 0) {
                _chat.clear();
                unawaited(_chat.open());
              } else if (value == 2) {
                unawaited(_changeOnlineAnswers(!online));
              } else if (value == 3) {
                unawaited(_setReminders(off: !remindersOff));
              } else {
                unawaited(
                  ref.read(assistantMemoryProvider.notifier).setQuiet(!quiet),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 0, child: Text(context.tr('Clear chat'))),
              PopupMenuItem(
                value: 2,
                child: Text(
                  online
                      ? context.tr('Keep answers on this phone')
                      : context.tr('Answer with AI when online'),
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Text(
                  quiet
                      ? context.tr('Show tips on Home')
                      : context.tr('Pause tips on Home'),
                ),
              ),
              if (PipNudges.supported)
                PopupMenuItem(
                  value: 3,
                  child: Text(
                    remindersOff
                        ? context.tr('Turn on evening reminders')
                        : context.tr('Pause evening reminders'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Layout.readable),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.sm,
                    Gap.lg,
                    Gap.lg,
                  ),
                  itemCount: entries.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) return _Welcome(rig: _hero);
                    if (index == entries.length + 1) {
                      return _Working(
                        status: chat.status,
                        step: chat.step,
                        trail: chat.trail,
                        continues: entries.isNotEmpty && entries.last.fromPip,
                      );
                    }
                    final entry = entries[index - 1];
                    final first =
                        index == 1 ||
                        entries[index - 2].fromPip != entry.fromPip;
                    return _Appear(
                      key: ValueKey(entry.id),
                      child: _EntryView(
                        entry: entry,
                        first: first,
                        saved: chat.savedPlans.contains(entry.id),
                        onAction: _handle,
                        onLock: _lock,
                        onStart: (subject) =>
                            unawaited(_chat.startBlock(subject)),
                        onSave: (plan) =>
                            unawaited(_chat.savePlan(entry.id, plan)),
                        onSaveTimetable: (timetable) =>
                            unawaited(_chat.saveTimetable(entry.id, timetable)),
                        onUseTimetable: (timetable) =>
                            unawaited(_chat.useTimetableToday(timetable)),
                        onRemoveReminder: (id) =>
                            unawaited(_chat.deleteReminder(id)),
                        onReport: (id) => unawaited(_report(id)),
                        onGoal: (minutes) => unawaited(
                          _chat.choose(
                            Suggestion(
                              Copy.raw(
                                formatMinutes(
                                  minutes,
                                  locale: Localizations.localeOf(context),
                                ),
                              ),
                              Icons.flag_outlined,
                              AssistantAction(Act.goalSet, value: minutes),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          _SuggestionBar(
            suggestions: chat.suggestions,
            onTap: (s) => unawaited(_handle(s)),
          ),
          _Composer(controller: _input, onSend: _send),
        ],
      ),
    );
  }
}

/// Pip, full height, at the top of every conversation.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.rig});

  final MascotRig rig;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.xl),
      child: Column(
        children: [
          ExcludeSemantics(child: Mascot(rig: rig, width: 84)),
          const SizedBox(height: Gap.sm),
          Text(kBuddyName, style: tt.titleLarge),
          const SizedBox(height: 2),
          Text(
            context.tr('Your study buddy'),
            style: tt.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              context.tr(
                'Pip is an AI study assistant. Suggestions are meant for planning and motivation. Always check your school and exam schedules.',
              ),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and lifts a new line into place, once.
class _Appear extends StatelessWidget {
  const _Appear({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
    ),
    child: child,
  );
}

const double _avatarSize = 26;

/// Pip's small head beside the first line of each of its turns.
class _Avatar extends StatefulWidget {
  const _Avatar();

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  final _rig = MascotRig();

  @override
  void dispose() {
    _rig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Mascot(rig: _rig, width: _avatarSize, headOnly: true),
  );
}

class _EntryView extends StatelessWidget {
  const _EntryView({
    required this.entry,
    required this.first,
    required this.saved,
    required this.onAction,
    required this.onLock,
    required this.onStart,
    required this.onSave,
    required this.onSaveTimetable,
    required this.onUseTimetable,
    required this.onRemoveReminder,
    required this.onReport,
    required this.onGoal,
  });

  final ChatEntry entry;
  final bool first;
  final bool saved;
  final ValueChanged<Suggestion> onAction;
  final Future<void> Function(List<AppMinutes>, bool) onLock;
  final ValueChanged<String?> onStart;
  final ValueChanged<PlanCard> onSave;
  final ValueChanged<Timetable> onSaveTimetable;
  final ValueChanged<Timetable> onUseTimetable;
  final ValueChanged<int> onRemoveReminder;
  final ValueChanged<int> onReport;
  final ValueChanged<int> onGoal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final top = first ? Gap.md : Gap.xs;

    if (!entry.fromPip) {
      final said = entry.text ?? entry.copy?.of(context) ?? '';
      return Padding(
        padding: EdgeInsets.only(top: top, left: width * 0.16),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _CopyOnHold(
            text: said,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(20),
                  topEnd: Radius.circular(20),
                  bottomStart: Radius.circular(20),
                  bottomEnd: Radius.circular(6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  said,
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final card = entry.card;
    final Widget content = switch (card) {
      ReportCard() => ReportCardView(card: card),
      PlanCard() => PlanCardView(
        card: card,
        saved: saved,
        onStart: () => onStart(card.blocks.firstOrNull?.subjectId),
        onSave: () => onSave(card),
      ),
      LockCard() => LockCardView(card: card, onLock: onLock),
      ExamCard() => ExamCardView(card: card),
      GoalCard() => GoalCardView(card: card, onPick: onGoal),
      RemindersCard() => RemindersCardView(
        card: card,
        onRemove: onRemoveReminder,
      ),
      TimetableCard() => TimetableCardView(
        card: card,
        saved: saved,
        onSave: onSaveTimetable,
        onUseToday: onUseTimetable,
      ),
      ActionCard() => ActionCardView(card: card, onAction: onAction),
      null => _PipLine(entry: entry, first: first, onReport: onReport),
    };

    return Padding(
      padding: EdgeInsets.only(
        top: top,
        right: card == null ? width * 0.12 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: _avatarSize, child: first ? const _Avatar() : null),
          const SizedBox(width: Gap.sm),
          Flexible(child: content),
        ],
      ),
    );
  }
}

/// Pip's speech bubble shape: the first line of a turn points at its head.
BorderRadiusDirectional _pipBubble({required bool first}) =>
    BorderRadiusDirectional.only(
      topStart: Radius.circular(first ? 6 : 20),
      topEnd: const Radius.circular(20),
      bottomStart: const Radius.circular(20),
      bottomEnd: const Radius.circular(20),
    );

/// One line of Pip's, written in as it arrives. Hold to copy.
class _PipLine extends StatelessWidget {
  const _PipLine({
    required this.entry,
    required this.first,
    required this.onReport,
  });

  final ChatEntry entry;
  final bool first;
  final ValueChanged<int> onReport;

  /// Lines older than this were already seen and appear whole.
  static const _fresh = Duration(seconds: 3);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final text = entry.copy?.of(context) ?? '';
    final at = entry.at;
    final fresh =
        at != null &&
        DateTime.now().difference(at) < _fresh &&
        !MediaQuery.disableAnimationsOf(context);
    final bubble = _CopyOnHold(
      text: text,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: _pipBubble(first: first),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _WriteIn(
            text: text,
            animate: fresh,
            style: tt.bodyLarge?.copyWith(color: cs.onSurface, height: 1.4),
          ),
        ),
      ),
    );
    if (!entry.online) return bubble;
    // Generated answers carry a way to report them.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: bubble),
        IconButton(
          tooltip: context.tr('Report this answer'),
          onPressed: () => onReport(entry.id),
          icon: Icon(
            Icons.flag_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Why the user is reporting an answer: returns one of [reportReasons].
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final labels = {
      'harmful': context.tr('Inappropriate or harmful content'),
      'hate': context.tr('Harassment or hate speech'),
      'incorrect': context.tr('Incorrect or misleading advice'),
    };
    return AlertDialog(
      title: Text(context.tr('Report this answer')),
      content: RadioGroup<String>(
        groupValue: _reason,
        onChanged: (value) => setState(() => _reason = value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final reason in reportReasons)
              RadioListTile<String>(
                value: reason,
                contentPadding: EdgeInsets.zero,
                title: Text(labels[reason]!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(_reason),
          child: Text(context.tr('Report')),
        ),
      ],
    );
  }
}

/// Writes [text] in from start to end, the way a reply streams in.
///
/// The whole text is laid out from the first frame and the unwritten part is
/// clear, so the bubble never changes size and nothing below it jumps. Screen
/// readers get the whole line at once.
class _WriteIn extends StatefulWidget {
  const _WriteIn({required this.text, required this.animate, this.style});

  final String text;
  final bool animate;
  final TextStyle? style;

  @override
  State<_WriteIn> createState() => _WriteInState();
}

class _WriteInState extends State<_WriteIn>
    with SingleTickerProviderStateMixin {
  /// Code-unit offsets of each character boundary, so a frame never splits
  /// a character (an emoji, a Devanagari cluster) in two.
  late List<int> _bounds;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _bounds = _boundsOf(widget.text);
    final count = _bounds.length - 1;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (count * 14).clamp(260, 1500)),
      value: widget.animate ? 0 : 1,
    );
    if (widget.animate) unawaited(_controller.forward());
  }

  @override
  void didUpdateWidget(_WriteIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _bounds = _boundsOf(widget.text);
      _controller.value = 1;
    }
  }

  static List<int> _boundsOf(String text) {
    final bounds = [0];
    var offset = 0;
    for (final char in text.characters) {
      offset += char.length;
      bounds.add(offset);
    }
    return bounds;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final text = widget.text;
        if (_controller.isCompleted) return Text(text, style: style);
        final count = _bounds.length - 1;
        final shown = (_controller.value * count).floor();
        // A few characters ahead of the pen come in half-inked.
        final soft = (shown + 6).clamp(0, count);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text.substring(0, _bounds[shown])),
              TextSpan(
                text: text.substring(_bounds[shown], _bounds[soft]),
                style: TextStyle(color: color.withValues(alpha: 0.35)),
              ),
              TextSpan(
                text: text.substring(_bounds[soft]),
                style: TextStyle(color: color.withValues(alpha: 0)),
              ),
            ],
          ),
          style: style,
        );
      },
    );
  }
}

/// Copies [text] when the bubble is held.
class _CopyOnHold extends StatelessWidget {
  const _CopyOnHold({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    onLongPressHint: context.tr('Copy message'),
    child: GestureDetector(
      onLongPress: text.isEmpty
          ? null
          : () {
              unawaited(Clipboard.setData(ClipboardData(text: text)));
              unawaited(HapticFeedback.selectionClick());
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(context.tr('Message copied.'))),
                );
            },
      child: child,
    ),
  );
}

/// Pip at work: the steps it has done, the one it is on, then dots while it
/// types. Its head thinks beside the bubble.
class _Working extends StatelessWidget {
  const _Working({
    required this.status,
    required this.step,
    this.trail = const [],
    this.continues = false,
  });

  final ChatStatus status;
  final Copy? step;
  final List<Copy> trail;

  /// Whether Pip already has a line just above, so this continues its turn
  /// without a second head.
  final bool continues;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (status == ChatStatus.idle) return const SizedBox(height: Gap.sm);
    final thinking = status == ChatStatus.thinking;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final current = step?.of(context) ?? context.tr('Thinking…');
    final muted = tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: EdgeInsets.only(top: continues ? Gap.xs : Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _avatarSize,
            child: continues ? null : _ThinkingAvatar(thinking: thinking),
          ),
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Semantics(
              liveRegion: true,
              label: thinking
                  ? current
                  : context.tr('{0} is typing', [kBuddyName]),
              excludeSemantics: true,
              child: AnimatedSize(
                duration: reduce ? Duration.zero : Motion.quick,
                curve: Curves.easeOutCubic,
                alignment: AlignmentDirectional.topStart,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: _pipBubble(first: !continues),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: !thinking
                        ? const TypingDots()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final done in trail)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Gap.sm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                        color: cs.primary,
                                      ),
                                      const SizedBox(width: Gap.sm),
                                      Flexible(
                                        child: Text(
                                          done.of(context),
                                          style: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const ExpressiveLoadingIndicator(size: 18),
                                  const SizedBox(width: Gap.sm),
                                  Flexible(
                                    child: _Shimmer(
                                      key: ValueKey(current),
                                      text: current,
                                      style: tt.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pip's head beside the thinking bubble, eyes up while it thinks.
class _ThinkingAvatar extends StatefulWidget {
  const _ThinkingAvatar({required this.thinking});

  final bool thinking;

  @override
  State<_ThinkingAvatar> createState() => _ThinkingAvatarState();
}

class _ThinkingAvatarState extends State<_ThinkingAvatar> {
  final _rig = MascotRig();

  @override
  void initState() {
    super.initState();
    _rig.thinking = widget.thinking;
  }

  @override
  void didUpdateWidget(_ThinkingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rig.thinking = widget.thinking;
    if (oldWidget.thinking && !widget.thinking) _rig.talk(seconds: 0.6);
  }

  @override
  void dispose() {
    _rig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Mascot(rig: _rig, width: _avatarSize, headOnly: true),
  );
}

/// The step Pip is on, with a light passing across it while it works. Still
/// with reduce motion on. Lives only as long as the step, so it always ends.
class _Shimmer extends StatefulWidget {
  const _Shimmer({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      widget.text,
      style: widget.style?.copyWith(color: cs.onSurfaceVariant),
    );
    if (MediaQuery.disableAnimationsOf(context)) return text;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [cs.onSurfaceVariant, cs.primary, cs.onSurfaceVariant],
          stops: const [0.35, 0.5, 0.65],
          transform: _Slide(_controller.value * 2 - 1),
        ).createShader(bounds),
        child: child,
      ),
      child: text,
    );
  }
}

/// Moves a gradient sideways by [fraction] of the box's width.
class _Slide extends GradientTransform {
  const _Slide(this.fraction);

  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final sign = textDirection == TextDirection.rtl ? -1 : 1;
    return Matrix4.translationValues(sign * fraction * bounds.width, 0, 0);
  }
}

class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({required this.suggestions, required this.onTap});

  final List<Suggestion> suggestions;
  final ValueChanged<Suggestion> onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.base,
      child: suggestions.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              key: ValueKey(suggestions),
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.xs,
                ),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return ActionChip(
                    avatar: Icon(suggestion.icon, size: 18),
                    label: Text(suggestion.label.of(context)),
                    onPressed: () => onTap(suggestion),
                  );
                },
              ),
            ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend = controller.text.trim().isNotEmpty;
    final pip = MascotColors.of(Theme.of(context));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.sm, Gap.md),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: context.tr('Message {0}', [kBuddyName]),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            // Pip's own orange with a white arrow, the same in light and
            // dark themes, rather than the pale primary of a dark scheme.
            IconButton.filled(
              onPressed: canSend ? onSend : null,
              tooltip: context.tr('Send'),
              style: IconButton.styleFrom(
                backgroundColor: pip.bodyDeep,
                foregroundColor: pip.face,
                disabledBackgroundColor: cs.onSurface.withValues(alpha: .12),
                disabledForegroundColor: cs.onSurface.withValues(alpha: .38),
              ),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
