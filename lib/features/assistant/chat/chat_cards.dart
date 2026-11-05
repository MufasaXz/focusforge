import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/exam_guide.dart';

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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: tt.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Gap.sm), trailing!],
        ],
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

class ReportCardView extends StatelessWidget {
  const ReportCardView({super.key, required this.card});

  final ReportCard card;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    String minutes(int m) => formatMinutes(m, locale: locale);
    return _CardShell(
      icon: Icons.insights_rounded,
      title: context.tr('Your week so far'),
      children: [
        _Row(
          label: context.tr('Today'),
          value: card.goalMinutes > 0
              ? context.tr('{0} of {1}', [
                  minutes(card.todayMinutes),
                  minutes(card.goalMinutes),
                ])
              : minutes(card.todayMinutes),
        ),
        if (card.goalMinutes > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: (card.todayMinutes / card.goalMinutes).clamp(0.0, 1.0),
                minHeight: 6,
              ),
            ),
          ),
        _Row(
          label: context.tr('This week'),
          value: minutes(card.weekMinutes),
          trailing: card.lastWeekSpanMinutes > 0
              ? _Delta(card.weekMinutes - card.lastWeekSpanMinutes)
              : null,
        ),
        if (card.streak > 0)
          _Row(
            label: context.tr('Streak'),
            value: context.tr('{0} days', [card.streak]),
          ),
        if (card.subjects.isNotEmpty) ...[
          _Subhead(context.tr('By subject')),
          for (final subject in card.subjects.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  _Dot(subject.color),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    minutes(subject.thisWeek),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (subject.lastWeekSpan > 0) ...[
                    const SizedBox(width: Gap.sm),
                    _Delta(subject.delta),
                  ],
                ],
              ),
            ),
        ],
        if (card.usageReady) ...[
          _Subhead(context.tr('Distracting apps today')),
          if (card.topApps.isEmpty)
            Text(minutes(0), style: TextStyle(color: cs.onSurfaceVariant))
          else
            for (final app in card.topApps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      Icons.apps_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(minutes(app.minutes)),
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
  });

  final PlanCard card;
  final bool saved;
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
