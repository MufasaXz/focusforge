import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Opens the sheet that edits the display name and persona.
///
/// A function rather than a bare widget so the caller never has to know how
/// the sheet is presented — the profile screen only decides *when*.
Future<void> showEditProfileSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // The keyboard must be able to push the sheet up rather than cover it.
    isScrollControlled: true,
    builder: (_) => const _EditProfileSheet(),
  );
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet();

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name;
  late Persona _persona;

  @override
  void initState() {
    super.initState();
    final user = ref.read(userProvider);
    _name = TextEditingController(text: user.displayName);
    _persona = user.persona;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    final notifier = ref.read(userProvider.notifier);
    await notifier.setDisplayName(_name.text);
    await notifier.setPersona(_persona);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        // The sheet lives under the floating nav bar, so it has to clear it
        // the same way the scroll views do.
        kNavBarClearance + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SheetSurface(
        // Inset from the screen on all sides, so this one rounds every corner
        // rather than only the top two.
        borderRadius: BorderRadius.circular(Radii.hero),
        padding: const EdgeInsets.all(Gap.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.lg),
              Text(
                'Edit profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Gap.lg),
              _FieldLabel(text: 'Display name'),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                style: Theme.of(context).textTheme.bodyLarge,
                cursorColor: cs.primary,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_valid) _save();
                },
                decoration: InputDecoration(
                  hintText: 'Your name',
                  hintStyle: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: cs.onSurfaceVariant),
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
              const SizedBox(height: Gap.lg),
              _FieldLabel(text: 'Persona'),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final p in Persona.values)
                    FilterChip(
                      selected: p == _persona,
                      onSelected: (_) => setState(() => _persona = p),
                      // The persona icon is the leading glyph; a checkmark
                      // would replace it when the chip is selected.
                      showCheckmark: false,
                      avatar: Icon(
                        p.icon,
                        size: 15,
                        color: p == _persona ? p.color : cs.onSurfaceVariant,
                      ),
                      label: Text(p.label),
                    ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              FilledButton.icon(
                onPressed: _valid ? _save : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save changes'),
              ),
            ],
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
