import '../../app/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/seed.dart';
import '../../core/models/subject_naming.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 4 — subjects, persona-aware.
///
/// Selecting a chip saves the subject immediately. Time allocations belong
/// to the Home goal planner and do not interrupt first-run setup.
class SubjectsStep extends ConsumerStatefulWidget {
  const SubjectsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<SubjectsStep> createState() => _SubjectsStepState();
}

class _SubjectsStepState extends ConsumerState<SubjectsStep> {
  final _selected = <String>{};
  final _custom = <SubjectTemplate>[];

  late final Persona _persona = ref.read(userProvider).persona;

  List<SubjectTemplate> get _templates => [
    ...SeedData.templatesFor(_persona),
    ..._custom,
  ];

  @override
  void initState() {
    super.initState();
    // The store, not this widget, is the source of truth: the flow's PageView
    // can dispose an off-screen step and rebuild it from scratch, so anything
    // held only in local state would quietly revert. Anything already in the
    // store starts selected, because that is genuinely what the app holds.
    final existing = ref.read(subjectsProvider);
    final templates = SeedData.templatesFor(_persona);
    final templateNames = {
      for (final template in templates) template.name.toLowerCase(),
    };

    for (final template in templates) {
      final match = existing
          .where((s) => s.name.toLowerCase() == template.name.toLowerCase())
          .firstOrNull;
      if (match == null) continue;
      _selected.add(template.name);
    }

    // A subject the user added by hand has no template to be rebuilt from, so
    // it comes back from the store here. Without this the chip disappears on
    // a rebuild while the subject stays in the provider — invisible to the
    // picker and still counted by the dashboard.
    for (final subject in existing) {
      if (templateNames.contains(subject.name.toLowerCase())) continue;
      final template = SubjectTemplate(
        subject.name,
        subject.icon,
        subject.color,
      );
      _custom.add(template);
      _selected.add(template.name);
    }
  }

  /// The store's key for a subject name.
  static String _slug(String name) => SubjectNaming.slug(name);

  Future<void> _toggle(SubjectTemplate template) async {
    final id = _slug(template.name);
    final notifier = ref.read(subjectsProvider.notifier);

    if (_selected.contains(template.name)) {
      setState(() {
        _selected.remove(template.name);
        // A deselected custom subject leaves the store, so it must leave the
        // picker too — a chip the provider no longer has would be a lie.
        // Persona templates stay: their list is static, so the chip can be
        // tapped back on.
        _custom.removeWhere((t) => t.name == template.name);
      });
      await notifier.remove(id);
      return;
    }

    setState(() {
      _selected.add(template.name);
    });
    await notifier.add(
      Subject(
        id: id,
        name: template.name,
        icon: template.icon,
        color: template.color,
      ),
    );
  }

  /// Why [rawName] cannot be added as a custom subject, or null when it can.
  ///
  /// The rule lives with the subject list it protects; the dialog only renders
  /// it. The unselected templates are reserved rather than stored, so a name
  /// the user has not picked yet is still a name they cannot take by hand.
  String? _collisionFor(String rawName) => SubjectNaming.reasonUnavailable(
    rawName,
    existing: ref.read(subjectsProvider),
    reserved: _templates.map((t) => t.name),
  );

  Future<void> _addCustom() async {
    final accent = Theme.of(context).colorScheme.secondary;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CustomSubjectDialog(validate: _collisionFor),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    final template = SubjectTemplate(
      name.trim(),
      Icons.bookmark_rounded,
      accent,
    );
    setState(() {
      _custom.add(template);
      _selected.add(template.name);
    });
    await ref
        .read(subjectsProvider.notifier)
        .add(
          Subject(
            id: _slug(template.name),
            name: template.name,
            icon: template.icon,
            color: template.color,
          ),
        );
  }

  /// Selections are already persisted when the chips are tapped.
  void _commit() {
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StepScaffold(
      title: _persona.subjectPrompt,
      subtitle: 'Pick your subjects or add your own.',
      primaryEnabled: _selected.isNotEmpty,
      primaryLabel: _selected.isEmpty
          ? 'Pick at least one'
          : 'Continue with ${_selected.length} ${_selected.length == 1 ? 'subject' : 'subjects'}',
      onPrimary: _commit,
      children: [
        Stagger(
          index: 2,
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final template in _templates)
                FilterChip(
                  selected: _selected.contains(template.name),
                  onSelected: (_) => _toggle(template),
                  avatar: Icon(
                    template.icon,
                    size: 18,
                    color: _selected.contains(template.name)
                        ? cs.onSurface
                        : harmonize(template.color, cs.primary),
                  ),
                  label: Text(template.name),
                ),
              FilterChip(
                selected: false,
                onSelected: (_) => _addCustom(),
                avatar: Icon(Icons.add_rounded, size: 18, color: cs.primary),
                label: const Text('Add custom'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomSubjectDialog extends StatefulWidget {
  const _CustomSubjectDialog({required this.validate});

  /// Returns the reason [name] cannot be added, or null when it can. The rule
  /// lives with the subject list it protects; the dialog only renders it.
  final String? Function(String name) validate;

  @override
  State<_CustomSubjectDialog> createState() => _CustomSubjectDialogState();
}

class _CustomSubjectDialogState extends State<_CustomSubjectDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // A rejection describes the text that caused it, so it must not outlive
    // that text: the first edit clears it.
    _controller.addListener(_clearError);
  }

  @override
  void dispose() {
    _controller.removeListener(_clearError);
    _controller.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  void _submit() {
    final name = _controller.text;
    if (name.trim().isNotEmpty) {
      final error = widget.validate(name);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(Gap.xl),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a subject',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Name it the way you think about it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.lg),
            AppTextField(
              controller: _controller,
              hint: 'e.g. Thesis',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Gap.lg),
            PrimaryAction(label: 'Add subject', onTap: _submit),
          ],
        ),
      ),
    );
  }
}
