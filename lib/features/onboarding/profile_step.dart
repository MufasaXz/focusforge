import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 3 — profile.
///
/// Name and timezone only. The avatar is initials rather than an upload: there
/// is no image pipeline yet, and a fake camera button that opens nothing is
/// worse than no button. The timezone is detected from the device clock — it
/// is needed for scheduled strictness and leaderboard resets, and asking the
/// user to type it would be a guaranteed typo.
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

  late final String _timezone = _detectTimezone();

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
  /// platform's own label plus the UTC offset is the honest thing to show.
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

  static String _initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Future<void> _commit() async {
    final notifier = ref.read(userProvider.notifier);
    final name = _name.text.trim();
    if (name.isNotEmpty) await notifier.setDisplayName(name);

    final profile = ref.read(userProvider);
    if (profile.timezone != _timezone) {
      await notifier.save(profile.copyWith(timezone: _timezone));
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final initials = _initialsOf(_name.text);

    return StepScaffold(
      title: 'Set up your profile',
      subtitle: 'Just the essentials — you can add the rest later.',
      onPrimary: _commit,
      children: [
        Stagger(
          index: 2,
          child: Center(child: _Avatar(initials: initials)),
        ),
        const SizedBox(height: Gap.xl),
        const Stagger(index: 3, child: SectionHeader(title: 'Display name')),
        Stagger(
          index: 4,
          child: GlassTextField(
            controller: _name,
            hint: 'Alex Rivera',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _commit(),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Stagger(
          index: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Leave it blank to stay nameless — everything still works.',
              style: context.type.bodySmall?.copyWith(color: t.textTertiary),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        const Stagger(index: 6, child: SectionHeader(title: 'Timezone')),
        Stagger(
          index: 7,
          child: GlassPanel(
            level: 2,
            radius: Radii.item,
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                GlassIconBadge(
                  icon: Icons.public_rounded,
                  color: t.success,
                  size: 36,
                  radius: Radii.tile,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detected from your device',
                        style: context.type.bodySmall?.copyWith(
                          color: t.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_timezone, style: context.type.titleSmall),
                    ],
                  ),
                ),
                GlassPill(
                  child: Text(
                    'Auto',
                    style: context.type.labelSmall?.copyWith(color: t.success),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.accentPrimary.withValues(alpha: 0.38),
            t.accentSecondary.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: t.accentPrimary.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: t.accentPrimary.withValues(alpha: 0.22),
            blurRadius: 26,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Center(
        child: initials.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: 38,
                color: t.accentPrimary.withValues(alpha: 0.9),
              )
            : Text(
                initials,
                style: context.type.displayMedium?.copyWith(fontSize: 32),
              ),
      ),
    );
  }
}
