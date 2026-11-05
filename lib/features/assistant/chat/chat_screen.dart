import 'dart:async';

import 'package:flutter/material.dart';
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
import '../home/pip_dock.dart' show TypingDots;
import '../mascot/mascot.dart';
import '../mascot/mascot_life.dart';
import '../mascot/mascot_rig.dart';
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

  void _onInput() => setState(() {});

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

    final status = switch (chat.status) {
      ChatStatus.thinking => chat.step?.of(context) ?? context.tr('Thinking…'),
      ChatStatus.typing => context.tr('Typing…'),
      ChatStatus.idle => context.tr('Your study buddy'),
    };
    final quiet = ref.watch(assistantMemoryProvider.select((m) => m.quiet));
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
                      return _Working(status: chat.status, step: chat.step);
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
    required this.onGoal,
  });

  final ChatEntry entry;
  final bool first;
  final bool saved;
  final ValueChanged<Suggestion> onAction;
  final Future<void> Function(List<AppMinutes>, bool) onLock;
  final ValueChanged<String?> onStart;
  final ValueChanged<PlanCard> onSave;
  final ValueChanged<int> onGoal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final top = first ? Gap.md : Gap.xs;

    if (!entry.fromPip) {
      return Padding(
        padding: EdgeInsets.only(top: top, left: width * 0.16),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                entry.text ?? entry.copy?.of(context) ?? '',
                style: tt.bodyLarge?.copyWith(
                  color: cs.onPrimary,
                  height: 1.35,
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
      ActionCard() => ActionCardView(card: card, onAction: onAction),
      null => DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(first ? 6 : 20),
            topEnd: const Radius.circular(20),
            bottomStart: const Radius.circular(20),
            bottomEnd: const Radius.circular(20),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            entry.copy?.of(context) ?? '',
            style: tt.bodyLarge?.copyWith(color: cs.onSurface, height: 1.4),
          ),
        ),
      ),
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

/// Pip at work: the step it is on, or dots while it types.
class _Working extends StatelessWidget {
  const _Working({required this.status, required this.step});

  final ChatStatus status;
  final Copy? step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (status == ChatStatus.idle) return const SizedBox(height: Gap.sm);
    final thinking = status == ChatStatus.thinking;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: Row(
        children: [
          const SizedBox(width: _avatarSize + Gap.sm),
          Flexible(
            child: Semantics(
              liveRegion: true,
              label: thinking
                  ? (step?.of(context) ?? context.tr('Thinking…'))
                  : context.tr('{0} is typing', [kBuddyName]),
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: thinking
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ExpressiveLoadingIndicator(size: 18),
                            const SizedBox(width: Gap.sm),
                            Flexible(
                              child: Text(
                                step?.of(context) ?? context.tr('Thinking…'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        )
                      : const TypingDots(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
            IconButton.filled(
              onPressed: canSend ? onSend : null,
              tooltip: context.tr('Send'),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
