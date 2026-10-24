import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/subject_appearance.dart';
import '../../core/models/subject_naming.dart';
import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/goal_planner_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/form_controls.dart';
import '../../shared/widgets/sheet_chrome.dart';

Future<void> showManageSubjectsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManageSubjectsSheet(),
    );

class _ManageSubjectsSheet extends ConsumerStatefulWidget {
  const _ManageSubjectsSheet();

  @override
  ConsumerState<_ManageSubjectsSheet> createState() =>
      _ManageSubjectsSheetState();
}

class _ManageSubjectsSheetState extends ConsumerState<_ManageSubjectsSheet> {
  bool _busy = false;
  final _name = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    final subjects = ref.read(subjectsProvider);
    final name = _name.text.trim();
    final error = SubjectNaming.reasonUnavailable(name, existing: subjects);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(subjectsProvider.notifier)
          .add(
            Subject(
              id: SubjectNaming.slug(name),
              name: name,
              icon: SubjectAppearance.icon(name),
              color: SubjectAppearance.unusedColor(subjects),
              weekTarget: SeedData.defaultWeeklyTarget(
                ref.read(userProvider).persona,
              ),
            ),
          );
      _name.clear();
      ref.read(timerProvider.notifier).setSubject(SubjectNaming.slug(name));
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr("Could not add this subject. Try again."));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Subject subject) async {
    if (_busy) return;
    final allocated =
        ref
            .read(focusGoalPlannerProvider)
            .day
            ?.subjectMinutes
            .containsKey(subject.id) ??
        false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.tr("Remove {0}?", [subject.name])),
        content: Text(
          context.tr(
            "Completed sessions and earned focus time stay in your history.{0}",
            [
              allocated
                  ? '\n\nYour daily target stays the same. Its subject split will be cleared so you can plan it again.'
                  : '',
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("Remove")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(subjectsProvider.notifier).remove(subject.id);
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Could not remove this subject. Try again."),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SheetSurface(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr("Manage subjects"),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      SheetCloseButton(onTap: () => Navigator.pop(context)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: Text(
                      context.tr("Add a subject or tidy your list."),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      labelText: context.tr("Subject name"),
                      hintText: context.tr("e.g. Mathematics"),
                      errorText: _error,
                      prefixIcon: Icon(SubjectAppearance.icon(_name.text)),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  FilledButton.icon(
                    onPressed: _busy || _name.text.trim().isEmpty ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.tr("Add subject")),
                  ),
                  const SizedBox(height: Gap.md),
                  if (subjects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Gap.xl,
                        horizontal: Gap.lg,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 30,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            context.tr("No subjects yet"),
                            style: theme.textTheme.titleSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            context.tr(
                              "Add your first above — it gets a colour and an icon on its own.",
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(Radii.item),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.item),
                        child: Column(
                          children: [
                            for (var i = 0; i < subjects.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 68,
                                  endIndent: Gap.md,
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              _SubjectRow(
                                subject: subjects[i],
                                busy: _busy,
                                onRemove: () => _remove(subjects[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One subject in the manager: its colour chip, its name and its weekly target.
///
/// The icon sits inside the subject's own colour so the row is recognisable at
/// the glance the picker trades in — a bare icon in the accent says nothing
/// about which subject it belongs to.
class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.busy,
    required this.onRemove,
  });

  final Subject subject;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = harmonize(subject.color, cs.primary);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: Gap.md, right: Gap.xs),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(subject.icon, size: 19, color: color),
      ),
      title: Text(
        subject.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      // The target and how much of it is banked this week — so the row is a
      // status, not just a name with a delete button. `weekDone`/`weekTarget`
      // are stored in hours; `formatHoursShort` writes them as hours.
      subtitle: Text(
        subject.weekDone > 0
            ? context.tr("{0} of {1} done this week", [
                formatHoursShort(subject.weekDone),
                formatHoursShort(subject.weekTarget),
              ])
            : context.tr("{0} a week", [
                formatHoursShort(subject.weekTarget),
              ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.labelSmall?.copyWith(
          color: subject.weekDone > 0 ? color : cs.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        tooltip: context.tr("Remove {0}", [subject.name]),
        onPressed: busy ? null : onRemove,
        icon: Icon(
          Icons.remove_circle_outline_rounded,
          color: cs.error.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
