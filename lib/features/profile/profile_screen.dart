import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/data/mock_data.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import '../../shared/widgets/progress_ring.dart';

/// Tab 4 — identity, progression and settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.lg + 4,
        MediaQuery.paddingOf(context).top + Gap.xl,
        Gap.lg + 4,
        kNavBarClearance,
      ),
      children: [
        // Hero ---------------------------------------------------------------
        GlassPanel(
          radius: Radii.hero,
          blur: 18,
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          t.accentPrimary.withValues(alpha: 0.85),
                          t.accentSecondary.withValues(alpha: 0.85),
                        ],
                      ),
                      border: Border.all(
                        color: t.specular,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: t.accentPrimary.withValues(alpha: 0.35),
                          blurRadius: 22,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      DemoData.userInitials,
                      style: context.type.titleLarge?.copyWith(
                        color: const Color(0xFF0A1020),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DemoData.userFullName,
                          style: context.type.titleLarge,
                        ),
                        const SizedBox(height: Gap.sm),
                        Row(
                          children: [
                            GlassPill(
                              selected: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Gap.md,
                                vertical: 5,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    DemoData.personaIcon,
                                    size: 12,
                                    color: t.accentPrimary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    DemoData.persona,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  Expanded(
                    child: _HeroStat(
                      value: '${DemoData.totalHours}h',
                      label: 'Total focus',
                    ),
                  ),
                  _Divider(t: t),
                  Expanded(
                    child: _HeroStat(
                      value: '${DemoData.streakDays}',
                      label: 'Day streak',
                      accent: t.gold,
                    ),
                  ),
                  _Divider(t: t),
                  Expanded(
                    child: _HeroStat(
                      value:
                          '${DemoData.achievements}/${DemoData.achievementsTotal}',
                      label: 'Badges',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              // Level + XP
              Row(
                children: [
                  Text(
                    'Level ${DemoData.level}',
                    style: context.type.titleSmall,
                  ),
                  const Spacer(),
                  Text(
                    '${DemoData.xp} / ${DemoData.xpForNext} XP',
                    style: context.type.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              GlassProgressBar(
                value: DemoData.xp / DemoData.xpForNext,
                color: t.accentSecondary,
                height: 7,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Study goals ---------------------------------------------------------
        const SectionHeader(
          title: 'Weekly study goals',
          icon: Icons.flag_rounded,
        ),
        EdgeFade(
          trailing: 32,
          child: SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: DemoData.subjects.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) {
                final s = DemoData.subjects[i];
                return GlassPanel(
                  radius: Radii.card,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.lg,
                    vertical: Gap.md,
                  ),
                  child: Row(
                    children: [
                      MiniRing(
                        value: s.weekProgress,
                        color: s.color,
                        size: 54,
                        label: '${(s.weekProgress * 100).round()}%',
                      ),
                      const SizedBox(width: Gap.md),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(s.icon, size: 13, color: s.color),
                              const SizedBox(width: 6),
                              Text(s.name, style: context.type.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${s.weekDone}h / ${s.weekTarget}h',
                            style: context.type.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Settings -------------------------------------------------------------
        const SectionHeader(title: 'Settings', icon: Icons.settings_rounded),
        GlassPanel(
          radius: Radii.card,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.xs,
          ),
          child: Column(
            children: [
              const _ThemeRow(),
              for (final s in DemoData.settings) ...[
                Divider(color: t.hairline, height: 1),
                _SettingTile(row: s),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    this.accent,
  });

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      children: [
        Text(
          value,
          style: context.type.titleLarge?.copyWith(
            color: accent ?? t.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: context.type.labelSmall?.copyWith(fontSize: 10.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.t});

  final GlassTokens t;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: t.hairline);
}

/// Dark / light switch. Kept inline so the design system can be inspected in
/// both modes without leaving the app.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        children: [
          GlassIconBadge(
            icon: Icons.dark_mode_rounded,
            color: t.accentSecondary,
            size: 36,
            radius: 10,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text('Dark appearance', style: context.type.bodyLarge),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (context, mode, _) => GlassToggle(
              value: mode == ThemeMode.dark,
              accent: t.accentSecondary,
              onChanged: (v) => themeMode.value =
                  v ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.row});

  final SettingRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Pressable(
      onTap: () {},
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(
          children: [
            GlassIconBadge(
              icon: row.icon,
              color: t.accentPrimary,
              size: 36,
              radius: 10,
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(row.label, style: context.type.bodyLarge)),
            if (row.trailing != null) ...[
              Text(
                row.trailing!,
                style: context.type.labelSmall?.copyWith(
                  color: t.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: t.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
