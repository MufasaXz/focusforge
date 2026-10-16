import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
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
        title: Text('Remove ${subject.name}?'),
        content: Text(
          'Completed sessions and earned focus time stay in your history.'
          '${allocated ? '\n\nYour daily target stays the same. Its subject split will be cleared so you can plan it again.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
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
          'Could not remove this subject. Try again.',
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
                        'Manage subjects',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    SheetCloseButton(onTap: () => Navigator.pop(context)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: Text(
                    'Keep the subjects you focus on. Your history stays saved.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Column(
                  children: [
                    if (subjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(Gap.xl),
                        child: Text(
                          'No subjects yet',
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
                          tooltip: 'Remove ${subject.name}',
                          onPressed: _busy ? null : () => _remove(subject),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
