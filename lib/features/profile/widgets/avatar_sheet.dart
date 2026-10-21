import '../../../core/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/profile_photo.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/icon_registry.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Opens the sheet that chooses the avatar's mark and colour.
Future<void> showAvatarSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const AvatarSheet(),
  );
}

/// The avatar, as a glyph on a colour — or the initials, which are the default
/// and stay one tap away.
///
/// Every change is written as it is made rather than on a Save button: there
/// is nothing to get wrong, the preview at the top is the real thing, and a
/// form with one control that has already applied itself is a form that lies.
class AvatarSheet extends ConsumerStatefulWidget {
  const AvatarSheet({super.key});

  @override
  ConsumerState<AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<AvatarSheet> {
  bool _picking = false;

  Future<void> _choosePhoto() async {
    if (_picking) return;
    final uid = ref.read(userProvider).uid;
    setState(() => _picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (image == null) return;
      final photo = await compute(
        ProfilePhoto.encode,
        await image.readAsBytes(),
      );
      if (!mounted || ref.read(userProvider).uid != uid) return;
      await ref.read(userProvider.notifier).setPhoto(photo);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Could not open this photo. Try another image.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// The colours on offer: the subject palette plus the scheme's own primary,
  /// so an avatar can match a subject or the app.
  List<Color> _colors(ColorScheme cs) => [
    cs.primary,
    ...SubjectPalette.harmonized(cs.primary),
    cs.secondary,
    cs.tertiary,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = ref.watch(userProvider);
    final notifier = ref.read(userProvider.notifier);
    final colors = _colors(cs);
    final selected = user.avatarColor == null
        ? null
        : colors.indexWhere((c) => c.toARGB32() == user.avatarColor);
    final mark = user.avatarIcon;

    return SheetSurface(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr("Your avatar"), style: tt.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          context.tr(
                            "Your photo is backed up with your account and shared when leaderboard sharing is on.",
                          ),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SheetCloseButton(
                    label: context.tr("Done"),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              Center(
                child: AvatarDisc(
                  user: user,
                  size: 96,
                  level: ref.watch(statsProvider).level,
                ),
              ),
              const SizedBox(height: Gap.md),
              FilledButton.tonalIcon(
                onPressed: _picking ? null : _choosePhoto,
                icon: _picking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(context.tr('Choose photo')),
              ),
              if (user.avatarPhoto != null)
                TextButton(
                  onPressed: _picking ? null : () => notifier.setPhoto(null),
                  child: Text(context.tr('Remove photo')),
                ),
              const SizedBox(height: Gap.xl),
              _FieldLabel(text: context.tr("Mark")),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  // Initials first, and always available: they are what the
                  // avatar is before anything is chosen, so they have to be
                  // something it can go back to.
                  _MarkChoice(
                    selected: mark == null,
                    accent: user.avatarColor == null
                        ? cs.primary
                        : Color(user.avatarColor!),
                    onTap: () =>
                        notifier.setAvatar(icon: null, color: user.avatarColor),
                    child: Text(
                      user.initials,
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final name in AppIcons.curated)
                    _MarkChoice(
                      selected: mark == name,
                      accent: user.avatarColor == null
                          ? cs.primary
                          : Color(user.avatarColor!),
                      onTap: () => notifier.setAvatar(
                        icon: name,
                        color: user.avatarColor,
                      ),
                      child: Icon(AppIcons.resolve(name), size: 19),
                    ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              _FieldLabel(text: context.tr("Colour")),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (var i = 0; i < colors.length; i++)
                    _ColorChoice(
                      color: colors[i],
                      selected: selected == i,
                      onTap: () =>
                          notifier.setAvatarColor(colors[i].toARGB32()),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatar itself, wherever it is drawn.
///
/// One widget for the profile header and the sheet's preview, so what the
/// user is choosing and what they will see afterwards cannot be two different
/// things.
class AvatarDisc extends StatelessWidget {
  const AvatarDisc({
    super.key,
    required this.user,
    required this.size,
    this.level = 1,
    this.editable = false,
  });

  final UserProfile user;
  final double size;
  final int level;

  static const _frameNames = ['Bronze', 'Silver', 'Gold', 'Emerald', 'Diamond'];

  static String frameNameForLevel(int level) =>
      _frameNames[(level.clamp(1, GamificationStats.maxLevel) - 1) ~/ 10];

  /// Draws the small pencil badge, and says "tap to change" to a screen
  /// reader. The tap itself belongs to the caller.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = user.avatarColor == null
        ? cs.primaryContainer
        : Color(user.avatarColor!);
    final onColor = user.avatarColor == null
        ? cs.onPrimaryContainer
        : _inkOn(color);
    final icon = user.avatarIcon;
    final photo = ProfilePhoto.bytes(user.avatarPhoto);
    final tier = (level.clamp(1, GamificationStats.maxLevel) - 1) ~/ 10;

    final label = user.displayName.trim().isEmpty
        ? context.tr("Profile avatar")
        : context.tr("Avatar for {0}", [user.displayName]);

    return Semantics(
      image: true,
      label: context.tr("{0}. Level {1}, {2} frame{3}", [
        label,
        level,
        context.tr(frameNameForLevel(level)),
        editable ? context.tr(". Tap to change it") : '',
      ]),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: EdgeInsets.all(size * .1),
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: photo != null
                  ? ClipOval(
                      child: Image.memory(
                        photo,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Center(child: Text(user.initials)),
                      ),
                    )
                  : Center(
                      child: icon == null
                          ? Text(
                              user.initials,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: onColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: size * 0.34,
                                  ),
                            )
                          : Icon(
                              AppIcons.resolve(icon),
                              size: size * 0.46,
                              color: onColor,
                            ),
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _AvatarFrame(tier: tier)),
              ),
            ),
            if (editable)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: size * 0.32,
                  height: size * 0.32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    size: size * 0.16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Black or white ink for [background], by its own luminance.
  ///
  /// The colour is a free choice — any of the palette, plus the scheme's own
  /// accents — so the ink cannot be looked up in the scheme the way a
  /// container colour's can.
  static Color _inkOn(Color background) =>
      background.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
}

class _AvatarFrame extends CustomPainter {
  const _AvatarFrame({required this.tier});

  final int tier;

  static const _colors = [
    Color(0xFFB77B51),
    Color(0xFF91A6BB),
    Color(0xFFD4A437),
    Color(0xFF39A880),
    Color(0xFF8C83E8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final color = _colors[tier];
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = tier == 0 ? 2 : 2.5;
    if (tier == 4) {
      paint.shader = const SweepGradient(
        colors: [Color(0xFF8C83E8), Color(0xFF6ED5E0), Color(0xFF8C83E8)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }
    canvas.drawCircle(center, radius, paint);
    if (tier > 0) {
      paint.strokeWidth = 1;
      canvas.drawCircle(center, radius - 4, paint);
    }
    if (tier > 1) {
      paint
        ..style = PaintingStyle.fill
        ..shader = null;
      final count = tier == 2
          ? 4
          : tier == 3
          ? 8
          : 12;
      for (var i = 0; i < count; i++) {
        final angle = i * math.pi * 2 / count - math.pi / 2;
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * radius;
        canvas.drawCircle(point, tier == 4 ? 2.3 : 1.7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AvatarFrame oldDelegate) => oldDelegate.tier != tier;
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

class _MarkChoice extends StatelessWidget {
  const _MarkChoice({
    required this.selected,
    required this.accent,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

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
            child: Center(
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? accent : cs.onSurfaceVariant,
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: selected ? accent : cs.onSurfaceVariant,
                  ),
                  child: child,
                ),
              ),
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
