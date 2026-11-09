import '../../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/sheet_chrome.dart';
import 'avatar_sheet.dart';

/// Opens the sheet that edits the profile: the avatar and the display name,
/// in one place.
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
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(userProvider);
    _name = TextEditingController(text: user.displayName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  /// One save at a time. The sheet closes only once the name is stored;
  /// a failure keeps the typed name and says so.
  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userProvider.notifier).setDisplayName(_name.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.tr("Could not save your profile. Try again.");
        });
      }
    }
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
                context.tr("Edit profile"),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Gap.lg),
              // The avatar is part of the profile, so it is changed from the
              // same sheet as the name. It follows the live profile, so a new
              // photo or mark shows here the moment it is chosen.
              Center(
                child: AvatarDisc(
                  user: ref.watch(userProvider),
                  size: 88,
                  level: ref.watch(statsProvider.select((s) => s.level)),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Center(
                child: TextButton.icon(
                  onPressed: () => showAvatarSheet(context),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(context.tr("Change your avatar")),
                ),
              ),
              const SizedBox(height: Gap.lg),
              _FieldLabel(text: context.tr("Display name")),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _name,
                // The board and groups cap a display name at 60 characters;
                // longer input is refused here rather than failing to publish.
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                style: Theme.of(context).textTheme.bodyLarge,
                cursorColor: cs.primary,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: context.tr("Your name"),
                  counterText: '',
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
              if (_error case final error?) ...[
                const SizedBox(height: Gap.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.error),
                  ),
                ),
              ],
              const SizedBox(height: Gap.xl),
              FilledButton.icon(
                onPressed: _valid && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(context.tr("Save changes")),
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
