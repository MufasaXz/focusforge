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
                  Column(
                    children: [
                      if (subjects.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(Gap.xl),
                          child: Text(
                            context.tr("No subjects yet"),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final subject in subjects)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Gap.xs,
                          ),
                          leading: Icon(
                            subject.icon,
                            color: harmonize(
                              subject.color,
                              theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(subject.name),
                          trailing: IconButton(
                            tooltip: context.tr("Remove {0}", [subject.name]),
                            onPressed: _busy ? null : () => _remove(subject),
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                            ),
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
    );
  }
}
