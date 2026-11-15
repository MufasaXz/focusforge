import '../../../core/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/profile_photo.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/user.dart';
import '../../../core/models/study_avatar.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/avatars/study_portrait.dart';
import '../../../shared/widgets/sheet_chrome.dart';

Future<void> showAvatarSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AvatarSheet(),
    );

class AvatarSheet extends ConsumerStatefulWidget {
  const AvatarSheet({super.key});
  @override
  ConsumerState<AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<AvatarSheet> {
  bool _busy = false;
  Future<void> _choosePhoto() async {
    if (_busy) return;
    final uid = ref.read(userProvider).uid;
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(StudyAvatar avatar) async {
    if (_busy || !avatar.unlockedAt(ref.read(statsProvider).level)) return;
    setState(() => _busy = true);
    try {
      await ref.read(userProvider.notifier).setStudyAvatar(avatar);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your avatar. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = ref.watch(userProvider);
    final level = ref.watch(statsProvider.select((s) => s.level));
    final selected = user.avatarPhoto == null
        ? StudyAvatar.fromId(user.avatarIcon)
        : null;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: SheetSurface(
          child: Column(
            children: [
              const SizedBox(height: Gap.md),
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Your avatar'),
                            style: tt.headlineSmall,
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            context.tr(
                              'A new companion every 5 levels. You’re at level {0}.',
                              [level],
                            ),
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: context.tr('Close'),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 20;
                    final columns = largeText || bounds.maxWidth < 340 ? 2 : 3;
                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent:
                            124 +
                            MediaQuery.textScalerOf(context).scale(20) * 2 +
                            MediaQuery.textScalerOf(context).scale(16) * 2,
                        crossAxisSpacing: Gap.sm,
                        mainAxisSpacing: Gap.sm,
                      ),
                      itemCount: StudyAvatar.values.length,
                      itemBuilder: (context, i) {
                        final avatar = StudyAvatar.values[i];
                        final unlocked = avatar.unlockedAt(level);
                        final active = selected == avatar;
                        final detail = unlocked
                            ? (active ? 'Selected' : 'Unlocked')
                            : 'Level ${avatar.unlockLevel}';
                        return Semantics(
                          button: true,
                          selected: active,
                          enabled: unlocked && !_busy,
                          label: '${avatar.label}, $detail',
                          excludeSemantics: true,
                          child: Material(
                            color: active
                                ? cs.primaryContainer.withValues(alpha: .4)
                                : cs.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: active
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: .4),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey(avatar.id),
                              onTap: unlocked && !_busy
                                  ? () => _select(avatar)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(Gap.sm),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Opacity(
                                      opacity: unlocked ? 1 : .55,
                                      child: StudyPortrait(
                                        avatar: avatar,
                                        size: 78,
                                      ),
                                    ),
                                    const SizedBox(height: Gap.sm),
                                    Text(
                                      avatar.label,
                                      style: tt.labelLarge,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          unlocked
                                              ? (active
                                                    ? Icons.check_circle_rounded
                                                    : Icons.check_rounded)
                                              : Icons.lock_outline_rounded,
                                          size: 13,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            context.tr(detail),
                                            style: tt.labelSmall,
                                            textAlign: TextAlign.center,
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
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: Gap.sm,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _choosePhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(context.tr('Use your photo')),
                    ),
                    if (user.avatarPhoto != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _select(StudyAvatar.scout),
                        child: Text(context.tr('Remove photo')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AvatarDisc extends StatelessWidget {
  const AvatarDisc({
    super.key,
    required this.user,
    required this.size,
    this.level = 1,
    this.editable = false,
    this.frame = true,
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

  /// The level frame around the disc. Setup leaves it off: there is no level
  /// to show before the first session.
  final bool frame;

  /// A chosen portrait, with initials retained for existing named profiles.
  Widget _mark(BuildContext context, String? icon, Color onColor) {
    if (icon != null || user.initials.isEmpty) {
      return StudyPortrait(
        avatar: StudyAvatar.forProfile(icon, level),
        size: size,
      );
    }
    final initials = user.initials;
    return Center(
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.primaryContainer;
    final onColor = cs.onPrimaryContainer;
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
                        // A photo that cannot be decoded falls back to the
                        // same mark as no photo at all.
                        errorBuilder: (context, _, _) =>
                            _mark(context, icon, onColor),
                      ),
                    )
                  : _mark(context, icon, onColor),
            ),
            if (frame)
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
