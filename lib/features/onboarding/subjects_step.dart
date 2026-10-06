import '../../app/theme/app_theme.dart';
import '../../shared/widgets/app_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 4 — subjects, persona-aware.
///
/// Selecting a chip writes the subject immediately rather than deferring to
/// the end of the flow: the list the user sees here is the list the dashboard
/// will render, so there is no "what did I actually pick?" moment. Weekly
/// targets are held locally only for the duration of a drag — a slider fires
/// continuously, so the store is written on drag end rather than every frame.
class SubjectsStep extends ConsumerStatefulWidget {
  const SubjectsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<SubjectsStep> createState() => _SubjectsStepState();
}

class _SubjectsStepState extends ConsumerState<SubjectsStep> {
  final _selected = <String>{};
  final _custom = <SubjectTemplate>[];
  final _targets = <String, double>{};

  late final Persona _persona = ref.read(userProvider).persona;

  /// A weekly target that scales with the persona's recommended daily goal,
  /// so a professional's subjects start hungrier than a parent's.
  double get _defaultWeekly =>
      (SeedData.goalSuggestions(_persona)[1] / 30).clamp(3, 8).toDouble();

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
      _targets[template.name] = match.weekTarget > 0
          ? match.weekTarget
          : _defaultWeekly;
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
      _targets[template.name] = subject.weekTarget > 0
          ? subject.weekTarget
          : _defaultWeekly;
    }
  }

  /// The store's key for a subject name.
  ///
  /// Lowercased and reduced to `[a-z0-9-]` so the id is stable across launches
  /// and safe to log. A name with no ASCII alphanumerics at all — "!!!", "📚",
  /// "数学" — reduces to nothing, and an empty id is not merely ugly: every
  /// such subject would share one key, so the second is rejected as a
  /// duplicate of the first and `remove`/`setWeeklyTarget` would hit all of
  /// them at once. The fallback encodes the code units instead, which is
  /// deterministic across launches in a way `String.hashCode` does not
  /// promise.
  static String _slug(String name) {
    final trimmed = name.trim();
    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isNotEmpty) return slug;
    // Radix-36 digits never contain '-', so the separator is unambiguous.
    return 's-${trimmed.codeUnits.map((u) => u.toRadixString(36)).join('-')}';
  }

  Future<void> _toggle(SubjectTemplate template) async {
    final id = _slug(template.name);
    final notifier = ref.read(subjectsProvider.notifier);

    if (_selected.contains(template.name)) {
      setState(() {
        _selected.remove(template.name);
        _targets.remove(template.name);
        // A deselected custom subject leaves the store, so it must leave the
        // picker too — a chip the provider no longer has would be a lie.
        // Persona templates stay: their list is static, so the chip can be
        // tapped back on.
        _custom.removeWhere((t) => t.name == template.name);
      });
      await notifier.remove(id);
      return;
    }

    final target = _defaultWeekly;
    setState(() {
      _selected.add(template.name);
      _targets[template.name] = target;
    });
    await notifier.add(
      Subject(
        id: id,
        name: template.name,
        icon: template.icon,
        color: template.color,
        weekTarget: target,
      ),
    );
  }

  /// Why [rawName] cannot be added as a custom subject, or null when it can.
  ///
  /// Names are the picker's identity and slug ids are the store's, so either
  /// can collide. A name that matches a template is skipped by the rebuild in
  /// [initState], which would drop the chip while the subject stayed in the
  /// store; two different names can also slug to one id — "Math!" against
  /// "Math" — and then `setWeeklyTarget` and `remove` would hit both subjects
  /// at once. Rejecting here, while the dialog is still open, keeps the
  /// message next to the field instead of failing silently.
  String? _collisionFor(String rawName) {
    final name = rawName.trim();
    final normalised = name.toLowerCase();
    final templates = _templates;

    for (final template in templates) {
      if (template.name.trim().toLowerCase() == normalised) {
        return '“${template.name}” is already on your list.';
      }
    }

    final id = _slug(name);
    for (final subject in ref.read(subjectsProvider)) {
      if (subject.id == id) {
        return 'That name is too similar to “${subject.name}”.';
      }
    }
    for (final template in templates) {
      if (_slug(template.name) == id) {
        return 'That name is too similar to “${template.name}”.';
      }
    }
    return null;
  }

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
      _targets[template.name] = _defaultWeekly;
    });
    await ref
        .read(subjectsProvider.notifier)
        .add(
          Subject(
            id: _slug(template.name),
            name: template.name,
            icon: template.icon,
            color: template.color,
            weekTarget: _defaultWeekly,
          ),
        );
  }

  /// Writes one weekly target through to the store. Called when a drag ends
  /// as well as on continue: the step can be disposed while the user is on
  /// another screen, and a target held only in local state would be lost.
  Future<void> _persistTarget(SubjectTemplate template, double value) async {
    final id = _slug(template.name);
    final notifier = ref.read(subjectsProvider.notifier);
    final exists = ref.read(subjectsProvider).any((s) => s.id == id);
    if (exists) {
      await notifier.setWeeklyTarget(id, value);
      return;
    }
    await notifier.add(
      Subject(
        id: id,
        name: template.name,
        icon: template.icon,
        color: template.color,
        weekTarget: value,
      ),
    );
  }

  Future<void> _commit() async {
    for (final template in _templates) {
      if (!_selected.contains(template.name)) continue;
      await _persistTarget(template, _targets[template.name] ?? _defaultWeekly);
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final recommended = SeedData.goalSuggestions(_persona)[1];
    final chosen = _templates
        .where((template) => _selected.contains(template.name))
        .toList(growable: false);

    return StepScaffold(
      title: _persona.subjectPrompt,
      subtitle:
          'Tap to select — or add your own. You can change these any '
          'time.',
      primaryEnabled: _selected.isNotEmpty,
      primaryLabel: _selected.isEmpty
          ? 'Pick at least one'
          : 'Continue with ${_selected.length}',
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
                        : template.color,
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
        const SizedBox(height: Gap.lg),
        Stagger(
          index: 3,
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 15, color: cs.tertiary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'Most ${_persona.label.toLowerCase()}s aim for '
                  '${formatMinutes(recommended)} of focus a day.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: Gap.xl),
          const Stagger(
            index: 4,
            child: SectionHeader(title: 'Weekly goal per subject'),
          ),
          for (var i = 0; i < chosen.length; i++)
            Stagger(
              index: 5 + i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: _TargetSlider(
                  template: chosen[i],
                  value: _targets[chosen[i].name] ?? _defaultWeekly,
                  onChanged: (v) =>
                      setState(() => _targets[chosen[i].name] = v),
                  onChangeEnd: (v) => unawaited(_persistTarget(chosen[i], v)),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TargetSlider extends StatelessWidget {
  const _TargetSlider({
    required this.template,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final SubjectTemplate template;
  final double value;
  final ValueChanged<double> onChanged;

  /// Commits the number once the drag settles. Persisting on [onChanged]
  /// would write the store on every frame of a drag.
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final label = value == value.roundToDouble()
        ? '${value.round()}h'
        : '${value.toStringAsFixed(1)}h';

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.item),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
        child: Column(
          children: [
            Row(
              children: [
                IconBadge(
                  icon: template.icon,
                  color: template.color,
                  size: 30,
                  radius: Radii.tile,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(template.name, style: Theme.of(context).textTheme.bodyLarge),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: template.color,
                  ),
                ),
                const SizedBox(width: Gap.sm),
              ],
            ),
            Slider(
              value: value.clamp(1, 20),
              min: 1,
              max: 20,
              divisions: 38,
              label: label,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
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
            Text('Add a subject', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Gap.sm),
            Text(
              'Name it the way you think about it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.lg),
            GlassTextField(
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
