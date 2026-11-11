import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/exam_guide.dart';
import '../brain/reminders.dart';
import '../brain/timetable.dart';
import 'chat_charts.dart';

/// The frame every card in the chat shares: a tonal panel with a titled
/// badge, so a report and a plan read as one family.
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A Material rather than a decorated box, so the rows inside a card can
    // show their own ink.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: icon,
                    color: cs.primary,
                    size: 32,
                    radius: 10,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: Gap.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A change against the same days last week, as an arrow and a length.
class _Delta extends StatelessWidget {
  const _Delta(this.minutes);

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (minutes == 0) return const SizedBox.shrink();
    final up = minutes > 0;
    final color = up ? cs.primary : cs.error;
    final amount = formatMinutes(
      minutes.abs(),
      locale: Localizations.localeOf(context),
    );
    return Semantics(
      label: up
          ? context.tr('{0} more than the same days last week', [amount])
          : context.tr('{0} less than the same days last week', [amount]),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 14,
            color: color,
          ),
          Text(
            amount,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: harmonize(color, Theme.of(context).colorScheme.primary),
      shape: BoxShape.circle,
    ),
  );
}

class _Subhead extends StatelessWidget {
  const _Subhead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// A big number under a small label: the reading a card leads with.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.trailing,
    this.hero = false,
  });

  final String label;
  final String value;
  final Widget? trailing;

  /// The card's headline number, set a size larger than the rest.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Gap.sm,
          children: [
            Text(
              value,
              style: (hero ? tt.headlineSmall : tt.titleLarge)?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

/// A row of a chart: what it is, how much, and a bar to compare by eye.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.lead,
    required this.name,
    required this.value,
    required this.bar,
    this.trailing,
  });

  final Widget lead;
  final String name;
  final String value;
  final Widget bar;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name at one edge, numbers at the other; with large text the
          // numbers drop to their own line instead of squeezing the name out.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Gap.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  lead,
                  const SizedBox(width: Gap.sm),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: Gap.sm),
                    trailing!,
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          ExcludeSemantics(child: bar),
        ],
      ),
    );
  }
}

/// The streak, worn in a card's corner.
class _StreakPill extends StatelessWidget {
  const _StreakPill(this.days);

  final int days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = context.tr('{0} days', [days]);
    return Semantics(
      label: '${context.tr('Streak')}: $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: Gap.xs),
              Text(
                text,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The week as a picture: the total, a column for each day, today against
/// its goal, then each subject and each distracting app as a bar.
class ReportCardView extends StatelessWidget {
  const ReportCardView({super.key, required this.card, this.animate = false});

  final ReportCard card;

  /// Whether the charts draw themselves in, for a card that has just arrived.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    final surface = cs.surfaceContainerLow;
    String minutes(int m) => formatMinutes(m, locale: locale);
    final subjects = card.subjects.take(5).toList();
    final subjectTop = subjects.fold(
      1,
      (top, t) => [top, t.thisWeek, t.lastWeekSpan].reduce(math.max),
    );
    final appTop = card.topApps.fold(1, (top, a) => math.max(top, a.minutes));
    return _CardShell(
      icon: Icons.insights_rounded,
      title: context.tr('Your week so far'),
      trailing: card.streak > 0 ? _StreakPill(card.streak) : null,
      children: [
        _Figure(
          label: context.tr('This week'),
          value: minutes(card.weekMinutes),
          hero: true,
          trailing: card.lastWeekSpanMinutes > 0
              ? _Delta(card.weekMinutes - card.lastWeekSpanMinutes)
              : null,
        ),
        const SizedBox(height: Gap.md),
        WeekBars(
          days: card.days,
          lastDays: card.lastDays,
          today: card.today,
          surface: surface,
          animate: animate,
        ),
        const SizedBox(height: Gap.md),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: _Figure(
                label: context.tr('Today'),
                value: card.goalMinutes > 0
                    ? context.tr('{0} of {1}', [
                        minutes(card.todayMinutes),
                        minutes(card.goalMinutes),
                      ])
                    : minutes(card.todayMinutes),
              ),
            ),
            if (card.goalMinutes > 0) ...[
              const SizedBox(width: Gap.md),
              GoalRing(
                share: card.todayMinutes / card.goalMinutes,
                animate: animate,
              ),
            ],
          ],
        ),
        if (subjects.isNotEmpty) ...[
          _Subhead(context.tr('By subject')),
          for (final subject in subjects)
            _BarRow(
              lead: _Dot(subject.color),
              name: subject.name,
              value: minutes(subject.thisWeek),
              trailing: subject.lastWeekSpan > 0 ? _Delta(subject.delta) : null,
              bar: AmountBar(
                value: subject.thisWeek / subjectTop,
                mark: subject.lastWeekSpan > 0
                    ? subject.lastWeekSpan / subjectTop
                    : null,
                color: harmonize(subject.color, cs.primary),
                surface: surface,
                animate: animate,
              ),
            ),
        ],
        if (card.usageReady) ...[
          _Subhead(context.tr('Distracting apps today')),
          if (card.topApps.isEmpty)
            Text(minutes(0), style: TextStyle(color: cs.onSurfaceVariant))
          else
            for (final app in card.topApps)
              _BarRow(
                lead: Icon(
                  Icons.apps_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                name: app.name,
                value: minutes(app.minutes),
                bar: AmountBar(
                  value: app.minutes / appTop,
                  color: cs.outline,
                  surface: surface,
                  animate: animate,
                ),
              ),
        ],
        if (card.notes.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: Gap.sm),
          for (final note in card.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(note.icon, size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      note.copy.of(context),
                      style: tt.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Study time over one period: the total, how it divides, and each subject's
/// share.
class BreakdownCardView extends StatelessWidget {
  const BreakdownCardView({
    super.key,
    required this.card,
    this.animate = false,
  });

  final BreakdownCard card;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    String minutes(int m) => formatMinutes(m, locale: locale);
    final shares = card.shares.take(6).toList();
    final whole = math.max(1, card.shares.fold(0, (sum, s) => sum + s.minutes));
    return _CardShell(
      icon: Icons.donut_small_rounded,
      title: card.title.of(context),
      children: [
        Row(
          children: [
            Expanded(
              child: _Figure(
                label: context.tr('Focus'),
                value: card.goalMinutes > 0
                    ? context.tr('{0} of {1}', [
                        minutes(card.totalMinutes),
                        minutes(card.goalMinutes),
                      ])
                    : minutes(card.totalMinutes),
              ),
            ),
            if (card.goalMinutes > 0) ...[
              const SizedBox(width: Gap.md),
              GoalRing(
                share: card.totalMinutes / card.goalMinutes,
                animate: animate,
              ),
            ],
          ],
        ),
        if (shares.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          PartsBar(
            parts: [for (final s in shares) (s.minutes, s.color)],
            animate: animate,
          ),
          const SizedBox(height: Gap.sm),
          for (final share in shares)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Row(
                children: [
                  _Dot(share.color),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      share.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Text(
                    minutes(share.minutes),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(48),
                    child: Text(
                      formatPercent(share.minutes / whole, locale: locale),
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class PlanCardView extends StatelessWidget {
  const PlanCardView({
    super.key,
    required this.card,
    required this.saved,
    required this.onStart,
    required this.onSave,
    this.animate = false,
  });

  final PlanCard card;
  final bool saved;
  final bool animate;
  final VoidCallback onStart;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    String minutes(int m) => formatMinutes(m, locale: locale);
    return _CardShell(
      icon: Icons.event_note_rounded,
      title: context.tr('Today’s plan'),
      children: [
        // The day's blocks in proportion, before the list spells them out.
        PartsBar(
          parts: [for (final b in card.blocks) (b.minutes, b.color)],
          animate: animate,
        ),
        const SizedBox(height: Gap.sm),
        for (final (i, block) in card.blocks.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                _Dot(block.color),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    block.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyLarge,
                  ),
                ),
                Text(
                  minutes(block.minutes),
                  style: tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.xs),
        Text(
          context.tr('Total {0}, with {1} breaks between blocks.', [
            minutes(card.totalMinutes),
            minutes(card.breakMinutes),
          ]),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(context.tr('Start first block')),
            ),
            OutlinedButton.icon(
              onPressed: saved ? null : onSave,
              icon: Icon(saved ? Icons.check_rounded : Icons.flag_outlined),
              label: Text(
                saved
                    ? context.tr('Saved as today’s goal')
                    : context.tr('Save as today’s goal'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class LockCardView extends StatefulWidget {
  const LockCardView({super.key, required this.card, required this.onLock});

  final LockCard card;

  /// Locks the chosen apps: during focus, or all day when [allDay].
  final Future<void> Function(List<AppMinutes> apps, bool allDay) onLock;

  @override
  State<LockCardView> createState() => _LockCardViewState();
}

class _LockCardViewState extends State<LockCardView> {
  late final Set<String> _chosen = {...widget.card.preselected};
  bool _done = false;
  bool _working = false;

  Future<void> _lock(bool allDay) async {
    setState(() => _working = true);
    await widget.onLock([
      for (final app in widget.card.apps)
        if (_chosen.contains(app.packageId)) app,
    ], allDay);
    if (mounted) {
      setState(() {
        _working = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final enabled = !_done && !_working && _chosen.isNotEmpty;
    return _CardShell(
      icon: Icons.shield_outlined,
      title: context.tr('Pick apps to lock'),
      trailing: _done
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
              semanticLabel: context.tr('Locked'),
            )
          : null,
      children: [
        for (final app in widget.card.apps)
          CheckboxListTile(
            value: _chosen.contains(app.packageId),
            onChanged: _done
                ? null
                : (on) => setState(
                    () => on == true
                        ? _chosen.add(app.packageId)
                        : _chosen.remove(app.packageId),
                  ),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: app.minutes > 0
                ? Text(
                    context.tr('{0} today', [
                      formatMinutes(app.minutes, locale: locale),
                    ]),
                  )
                : null,
          ),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            FilledButton.icon(
              onPressed: enabled ? () => _lock(false) : null,
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(context.tr('Lock while focusing')),
            ),
            TextButton(
              onPressed: enabled ? () => _lock(true) : null,
              child: Text(context.tr('Block all day')),
            ),
          ],
        ),
      ],
    );
  }
}

class ExamCardView extends StatelessWidget {
  const ExamCardView({super.key, required this.card});

  final ExamCard card;

  @override
  Widget build(BuildContext context) {
    final exam = examById(card.examId);
    if (exam == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget fact(IconData icon, String key) => Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(context.tr(key), style: tt.bodyMedium)),
        ],
      ),
    );
    return _CardShell(
      icon: Icons.school_outlined,
      title: AssistantBrain.examTitle(exam).of(context),
      trailing: card.isMine
          ? Chip(
              label: Text(context.tr('Your exam')),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      children: [
        Text(context.tr(exam.summary), style: tt.bodyMedium),
        fact(Icons.assignment_outlined, exam.pattern),
        fact(Icons.rule_rounded, exam.marking),
        fact(Icons.lightbulb_outline_rounded, exam.tip),
        const SizedBox(height: Gap.md),
        Text(
          context.tr('Patterns change. Check the latest official notice.'),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class GoalCardView extends StatelessWidget {
  const GoalCardView({super.key, required this.card, required this.onPick});

  final GoalCard card;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return _CardShell(
      icon: Icons.flag_outlined,
      title: context.tr('Daily goal'),
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final option in GoalCard.options)
              ChoiceChip(
                label: Text(formatMinutes(option, locale: locale)),
                selected: option == card.currentMinutes,
                onSelected: (_) => onPick(option),
              ),
          ],
        ),
      ],
    );
  }
}

class ActionCardView extends StatelessWidget {
  const ActionCardView({super.key, required this.card, required this.onAction});

  final ActionCard card;
  final ValueChanged<Suggestion> onAction;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Gap.sm,
    runSpacing: Gap.sm,
    children: [
      for (final action in card.actions)
        FilledButton.tonalIcon(
          onPressed: () => onAction(action),
          icon: Icon(action.icon),
          label: Text(action.label.of(context)),
        ),
    ],
  );
}

/// A timetable to shape before saving: the start time, each subject's
/// hours, and whether Pip should remind the user when it starts.
class TimetableCardView extends StatefulWidget {
  const TimetableCardView({
    super.key,
    required this.card,
    required this.saved,
    required this.onSave,
    required this.onUseToday,
  });

  final TimetableCard card;
  final bool saved;
  final ValueChanged<Timetable> onSave;
  final ValueChanged<Timetable> onUseToday;

  @override
  State<TimetableCardView> createState() => _TimetableCardViewState();
}

class _TimetableCardViewState extends State<TimetableCardView> {
  late Timetable _draft = widget.card.timetable;
  bool _edited = false;

  void _change(Timetable next) => setState(() {
    _draft = next;
    _edited = true;
  });

  String _name(BuildContext context, String id) =>
      widget.card.names[id] ?? context.tr('Study');

  Future<void> _pickStart() async {
    final start = _draft.effectiveStart;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
    );
    if (picked == null || !mounted) return;
    _change(_draft.copyWith(startMinute: picked.hour * 60 + picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    String minutes(int m) => formatMinutes(m, locale: locale);
    String clock(int m) => formatTimeOfDay(m, locale: locale);
    final saved = widget.saved && !_edited;
    final missing = [
      for (final id in widget.card.names.keys)
        if (!_draft.subjectMinutes.containsKey(id)) id,
    ];
    final figures = const [FontFeature.tabularFigures()];

    return _CardShell(
      icon: Icons.view_timeline_outlined,
      title: context.tr('Your timetable'),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionChip(
            avatar: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(
              context.tr('Starts at {0}', [clock(_draft.effectiveStart)]),
            ),
            onPressed: _pickStart,
          ),
        ),
        const SizedBox(height: Gap.xs),
        for (final MapEntry(key: id, value: m) in _draft.subjectMinutes.entries)
          Row(
            children: [
              _Dot(widget.card.colors[id] ?? cs.onSurfaceVariant),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  _name(context, id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyLarge,
                ),
              ),
              IconButton(
                tooltip: context.tr('Less {0}', [_name(context, id)]),
                onPressed: () => _change(_draft.adjust(id, -Timetable.step)),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  minutes(m),
                  textAlign: TextAlign.center,
                  style: tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: figures,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('More {0}', [_name(context, id)]),
                onPressed: _draft.totalMinutes >= Timetable.maxTotal
                    ? null
                    : () => _change(_draft.adjust(id, Timetable.step)),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        if (missing.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PopupMenuButton<String>(
              tooltip: context.tr('Add a subject'),
              // A full day has no room for another subject.
              enabled:
                  _draft.totalMinutes + Timetable.step <= Timetable.maxTotal,
              onSelected: (id) => _change(_draft.adjust(id, 60)),
              itemBuilder: (context) => [
                for (final id in missing)
                  PopupMenuItem(value: id, child: Text(_name(context, id))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: cs.primary),
                    const SizedBox(width: Gap.sm),
                    Text(
                      context.tr('Add a subject'),
                      style: tt.labelLarge?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Text(
          context.tr('{0} a day, in blocks of up to {1} with {2} breaks.', [
            minutes(_draft.totalMinutes),
            minutes(_draft.blockMinutes),
            minutes(_draft.breakMinutes),
          ]),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        _Subhead(context.tr('Break between sessions')),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          children: [
            for (final minutesOff in Timetable.breakChoices)
              ChoiceChip(
                label: Text(minutes(minutesOff)),
                selected: _draft.breakMinutes == minutesOff,
                onSelected: (_) =>
                    _change(_draft.copyWith(breakMinutes: minutesOff)),
              ),
          ],
        ),
        _Subhead(context.tr('Your day')),
        for (final slot in _draft.slots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 148,
                  child: Text(
                    '${clock(slot.start)} – ${clock(slot.end)}',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFeatures: figures,
                    ),
                  ),
                ),
                _Dot(widget.card.colors[slot.subjectId] ?? cs.onSurfaceVariant),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    _name(context, slot.subjectId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _draft.remind,
          onChanged: (on) => _change(_draft.copyWith(remind: on)),
          title: Text(context.tr('Remind me when it starts')),
        ),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            FilledButton.icon(
              onPressed: saved
                  ? null
                  : () {
                      setState(() => _edited = false);
                      widget.onSave(_draft);
                    },
              icon: Icon(saved ? Icons.check_rounded : Icons.save_outlined),
              label: Text(
                saved ? context.tr('Timetable saved') : context.tr('Save'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onUseToday(_draft),
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: Text(context.tr('Use as today’s focus plan')),
            ),
          ],
        ),
      ],
    );
  }
}

/// The user's reminders, soonest first, each with a button to remove it.
class RemindersCardView extends StatefulWidget {
  const RemindersCardView({
    super.key,
    required this.card,
    required this.onRemove,
  });

  final RemindersCard card;
  final ValueChanged<int> onRemove;

  @override
  State<RemindersCardView> createState() => _RemindersCardViewState();
}

class _RemindersCardViewState extends State<RemindersCardView> {
  final _removed = <int>{};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    final left = [
      for (final r in widget.card.reminders)
        if (!_removed.contains(r.id)) r,
    ];
    return _CardShell(
      icon: Icons.notifications_none_rounded,
      title: context.tr('Your reminders'),
      children: [
        if (left.isEmpty)
          Text(
            context.tr('No reminders left.'),
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        for (final StudyReminder r in left)
          Row(
            children: [
              Icon(
                r.exam ? Icons.school_outlined : Icons.event_outlined,
                size: 20,
                color: cs.primary,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyLarge,
                    ),
                    Text(
                      '${formatDate(r.at, locale: locale)} · '
                      '${formatTimeOfDay(r.at.hour * 60 + r.at.minute, locale: locale)}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('Remove reminder'),
                onPressed: () {
                  setState(() => _removed.add(r.id));
                  widget.onRemove(r.id);
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
      ],
    );
  }
}
