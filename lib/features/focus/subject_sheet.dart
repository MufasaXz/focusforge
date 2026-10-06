import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/models/subject_naming.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/sheet_chrome.dart';

/// Opens the sheet that creates a subject, and returns the one it made.
///
/// Returns null when the sheet is dismissed without adding, so the caller can
/// tell "they added a subject" from "they closed it" without watching the
/// provider.
Future<Subject?> showSubjectSheet(BuildContext context) {
  return showModalBottomSheet<Subject>(
    context: context,
    // Root navigator: the sheet has to float over the nav bar, not under it.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const SubjectSheet(),
  );
}

/// Creates one subject: a name, a glyph and a colour.
///
/// The name is the only required part — the glyph and the colour start on a
/// suggestion derived from the palette, because a subject added mid-session is
/// a name the user has in their head, not a design decision they want to make
/// before the timer can start.
class SubjectSheet extends ConsumerStatefulWidget {
  const SubjectSheet({super.key});

  @override
  ConsumerState<SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends ConsumerState<SubjectSheet> {
  /// The glyphs on offer, as names rather than code points: the stored icon
  /// crosses the storage boundary as a name, and a name that is not in the
  /// table would come back as a neutral circle.
  static const _iconNames = AppIcons.curated;

  final _name = TextEditingController();
  int _icon = 0;
  int _color = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    // Two reasons to rebuild on every keystroke: the primary action is
    // disabled while the field is empty, and a rejection describes the text
    // that caused it — so the first edit clears it.
    setState(() => _error = null);
  }

  List<Color> get _colors =>
      SubjectPalette.harmonized(Theme.of(context).colorScheme.primary);

  Future<void> _submit() async {
    final name = _name.text.trim();
    final error = SubjectNaming.reasonUnavailable(
      name,
      existing: ref.read(subjectsProvider),
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final subject = Subject(
      id: SubjectNaming.slug(name),
      name: name,
      icon: AppIcons.resolve(_iconNames[_icon]),
      color: _colors[_color % _colors.length],
      // The same starting target the onboarding picker uses, so a subject
      // added later is not the only one without a goal — and derived from
      // the persona rather than made up here.
      weekTarget: SeedData.defaultWeeklyTarget(ref.read(userProvider).persona),
    );
    await ref.read(subjectsProvider.notifier).add(subject);
    if (mounted) Navigator.of(context).pop(subject);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final colors = _colors;
    final preview = AppIcons.resolve(_iconNames[_icon]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetSurface(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.xl),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    // The preview is the whole point of the two pickers below:
                    // what is being chosen is one glyph on one colour.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors[_color % colors.length].withValues(
                          alpha: 0.18,
                        ),
                        borderRadius: BorderRadius.circular(Radii.tile),
                        border: Border.all(
                          color: colors[_color % colors.length].withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      child: Icon(
                        preview,
                        size: 22,
                        color: colors[_color % colors.length],
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New subject', style: tt.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Sessions you run with it selected are logged '
                            'against it.',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SheetCloseButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: tt.bodyLarge,
                  cursorColor: cs.primary,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'e.g. Thesis',
                    hintStyle: tt.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.md,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.item),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.item),
                      borderSide: BorderSide(color: cs.primary, width: 1.4),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Gap.md),
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: cs.error,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: tt.bodySmall?.copyWith(color: cs.error),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Gap.xl),
                _FieldLabel(text: 'Icon'),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (var i = 0; i < _iconNames.length; i++)
                      _IconChoice(
                        icon: AppIcons.resolve(_iconNames[i]),
                        accent: colors[_color % colors.length],
                        selected: i == _icon,
                        onTap: () => setState(() => _icon = i),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.xl),
                _FieldLabel(text: 'Colour'),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (var i = 0; i < colors.length; i++)
                      _ColorChoice(
                        color: colors[i],
                        selected: i == _color % colors.length,
                        onTap: () => setState(() => _color = i),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.xl),
                FilledButton.icon(
                  onPressed: _name.text.trim().isEmpty ? null : _submit,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add subject'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 1.3,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          scale: 0.88,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.18)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.tile),
              border: Border.all(
                color: selected ? accent : cs.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: selected ? accent : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          scale: 0.88,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: selected ? 0.22 : 0.10),
              border: Border.all(
                color: selected ? color : cs.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 16 : 13,
                height: selected ? 16 : 13,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
