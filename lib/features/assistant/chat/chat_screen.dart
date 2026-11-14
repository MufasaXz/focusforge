import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
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
      unawaited(_openChat());
    });
  }

  Future<void> _openChat() async {
    if (mounted) await _chat.open(action: widget.initial);
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
      var end = _scroll.position.maxScrollExtent;
      // A reply taller than the screen is read from its top: stop where
      // Pip's turn begins rather than at its last line.
      final entries = ref.read(chatProvider).entries;
      var start = entries.length;
      while (start > 0 && entries[start - 1].fromPip) {
        start--;
      }
      final turn = start < entries.length
          ? _EntryKey(entries[start].id).currentContext?.findRenderObject()
          : null;
      if (turn != null && turn.attached) {
        final top = RenderAbstractViewport.of(turn)
            .getOffsetToReveal(turn, 0)
            .offset;
        end = math.min(end, math.max(0, top - Gap.sm));
      }
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
    // Only a working Pip needs a second line; at rest the header is its name.
    final status = switch (chat.status) {
      ChatStatus.thinking => chat.step?.of(context) ?? context.tr('Thinking…'),
      ChatStatus.typing => context.tr('Typing…'),
      ChatStatus.idle => null,
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
                    child: status == null
                        ? const SizedBox.shrink()
                        : Text(
                            status,
                            key: ValueKey(status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: chat.busy
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
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
                      key: _EntryKey(entry.id),
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

/// Finds an entry's place on screen by its id, so the list can scroll to it.
class _EntryKey extends GlobalObjectKey {
  const _EntryKey(int super.id);
}

/// Pip, full height, at the top of every conversation.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.rig});

  final MascotRig rig;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // The header already names Pip, so the welcome is the figure, one line
    // of what it is for and an honest note — not a second title.
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.lg),
      child: Column(
        children: [
          ExcludeSemantics(child: Mascot(rig: rig, width: 64)),
          const SizedBox(height: Gap.sm),
          Text(
            context.tr('Your study buddy'),
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Gap.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              context.tr(
                'Pip works on this phone. Suggestions are for planning and motivation, so check your school and exam schedules too.',
              ),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
              // A soft tonal bubble rather than solid primary: the user's
              // words are easy to find without shouting over Pip's.
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(22),
                  topEnd: Radius.circular(22),
                  bottomStart: Radius.circular(22),
                  bottomEnd: Radius.circular(8),
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
                    color: cs.onPrimaryContainer,
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
    // A card that has just arrived draws its charts in; one scrolled back
    // to is already drawn.
    final at = entry.at;
    final fresh = at != null && DateTime.now().difference(at) < _PipLine._fresh;
    final Widget content = switch (card) {
      ReportCard() => ReportCardView(card: card, animate: fresh),
      BreakdownCard() => BreakdownCardView(card: card, animate: fresh),
      PlanCard() => PlanCardView(
        card: card,
        saved: saved,
        animate: fresh,
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
      null => _PipLine(entry: entry, first: first),
    };

    return Padding(
      padding: EdgeInsets.only(
        top: top,
        right: card == null ? width * 0.04 : 0,
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
  const _PipLine({required this.entry, required this.first});

  final ChatEntry entry;
  final bool first;

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
    final style = tt.bodyLarge?.copyWith(color: cs.onSurface, height: 1.45);
    final blocks = _Blocks.parse(text);
    // Pip's words sit on the page beside its face, the way current
    // assistants read: no grey bubble around every line. Longer answers
    // keep their structure — a title, then labelled paragraphs.
    return _CopyOnHold(
      text: text,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: blocks == null
            ? _WriteIn(text: text, animate: fresh, style: style)
            : _FadeIn(
                animate: fresh,
                child: _StructuredText(blocks: blocks, style: style),
              ),
      ),
    );
  }
}

/// A reply split into a title and paragraphs, some led by a label such as
/// "Example:" or "Watch out:". Null when the text is a plain line.
class _Blocks {
  const _Blocks(this.title, this.paragraphs);

  final String? title;
  final List<(String?, String)> paragraphs;

  static final _label = RegExp(
    r"^([A-Z][A-Za-z ’'-]{1,22}):\s+(.+)$",
    dotAll: true,
  );

  static _Blocks? parse(String text) {
    final parts = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    String? title;
    final first = parts.first;
    if (first.length <= 60 &&
        !first.contains('\n') &&
        !RegExp(r'[.!?]$').hasMatch(first)) {
      title = first;
      parts.removeAt(0);
    }
    final paragraphs = <(String?, String)>[
      for (final p in parts)
        if (_label.firstMatch(p) case final m?)
          (m.group(1), m.group(2)!)
        else
          (null, p),
    ];
    return _Blocks(title, paragraphs);
  }
}

class _StructuredText extends StatelessWidget {
  const _StructuredText({required this.blocks, required this.style});

  final _Blocks blocks;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocks.title case final title?) ...[
          Text(
            title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Gap.sm),
        ],
        for (final (i, (label, body)) in blocks.paragraphs.indexed) ...[
          if (i > 0) const SizedBox(height: Gap.md),
          if (label == null)
            Text(body, style: style)
          else
            // A labelled paragraph gets a quiet rule down its side, so
            // "Example" and "Watch out" read as asides at a glance.
            DecoratedBox(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: cs.primary.withValues(alpha: .5),
                    width: 3,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: tt.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: style),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Fades a structured reply in once, instead of writing it letter by letter.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) => !animate
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Motion.decelerate,
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: child,
        );
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
    // One field with the send button inside it, as messaging apps draw
    // it, instead of a pill and a separate round button beside it.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: Gap.sm, end: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
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
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // Pip's own orange with a white arrow, the same in light
                  // and dark, rather than the pale primary of a dark scheme.
                  child: IconButton.filled(
                    onPressed: canSend ? onSend : null,
                    tooltip: context.tr('Send'),
                    style: IconButton.styleFrom(
                      backgroundColor: pip.bodyDeep,
                      foregroundColor: pip.face,
                      disabledBackgroundColor: cs.onSurface.withValues(
                        alpha: .08,
                      ),
                      disabledForegroundColor: cs.onSurface.withValues(
                        alpha: .38,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
