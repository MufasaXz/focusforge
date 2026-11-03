import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../features/profile/widgets/avatar_sheet.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 3 — profile: a photo and a name, both optional.
///
/// The avatar opens the same sheet the Profile tab uses, so a photo chosen here
/// is the one shown everywhere afterwards. The timezone is still recorded,
/// from the device clock, because scheduled strictness and weekly resets need
/// it; it is not shown, since there is nothing for the user to decide.
class ProfileStep extends ConsumerStatefulWidget {
  const ProfileStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<ProfileStep> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(userProvider).displayName,
  );

  @override
  void initState() {
    super.initState();
    // The avatar mirrors the field, so every keystroke redraws the initials.
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  /// No timezone database is bundled, so the IANA name is out of reach; the
  /// platform's own label plus the UTC offset is what gets stored.
  static String _detectTimezone() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final minutes = abs.inMinutes % 60;
    final gmt =
        'GMT$sign${abs.inHours}'
        '${minutes == 0 ? '' : ':${minutes.toString().padLeft(2, '0')}'}';
    final name = now.timeZoneName;
    return name.isEmpty || name == gmt ? gmt : '$name ($gmt)';
  }

  Future<void> _commit() async {
    final notifier = ref.read(userProvider.notifier);
    final name = _name.text.trim();
    if (name.isNotEmpty) await notifier.setDisplayName(name);

    final timezone = _detectTimezone();
    final profile = ref.read(userProvider);
    if (profile.timezone != timezone) {
      await notifier.save(profile.copyWith(timezone: timezone));
    }
    if (mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(userProvider);
    // The preview follows the field before it is saved.
    final preview = user.copyWith(displayName: _name.text);
    final hasPhoto = user.avatarPhoto != null || user.avatarIcon != null;

    return StepScaffold(
      title: context.tr("Your profile"),
      subtitle: context.tr("What should we call you?"),
      onPrimary: _commit,
      children: [
        Stagger(
          index: 2,
          child: Center(
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: context.tr("Choose photo"),
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => showAvatarSheet(context),
                    scale: 0.95,
                    child: AvatarDisc(
                      user: preview,
                      size: 104,
                      editable: true,
                      frame: false,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                TextButton.icon(
                  onPressed: () => showAvatarSheet(context),
                  icon: Icon(
                    hasPhoto
                        ? Icons.edit_outlined
                        : Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(context.tr("Choose photo")),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Stagger(
          index: 3,
          child: Text(
            context.tr("Display name"),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Stagger(
          index: 4,
          child: AppTextField(
            controller: _name,
            hint: context.tr("Your name"),
            icon: Icons.person_outline_rounded,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Stagger(
          index: 5,
          child: Text(
            context.tr("Optional. You can change it later."),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
