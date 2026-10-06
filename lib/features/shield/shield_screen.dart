import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/shell/app_shell.dart';
import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/data/mock_data.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import '../../shared/widgets/segmented_control.dart';

/// Tab 2 — the shielding engine: feed blocking, whitelist tiers and profiles.
///
/// The header genuinely floats: the list scrolls underneath it and blurs as it
/// passes, which is the whole point of a frosted sticky bar.
class ShieldScreen extends StatefulWidget {
  const ShieldScreen({super.key});

  @override
  State<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends State<ShieldScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = 172 + topInset;

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Gap.lg + 4,
              headerHeight + Gap.md,
              Gap.lg + 4,
              kNavBarClearance,
            ),
            children: [
              switch (_segment) {
                0 => const _FeedBlockerView(),
                1 => const _WhitelistView(),
                _ => const _ProfilesView(),
              },
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  Gap.lg + 4,
                  topInset + Gap.lg,
                  Gap.lg + 4,
                  Gap.lg,
                ),
                // A dark scrim that dissolves into the content, rather than a
                // light translucent slab — on a dark canvas a white-tinted
                // header reads as a different theme entirely.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      t.canvasGradient.first.withValues(alpha: 0.96),
                      t.canvasGradient[1].withValues(alpha: 0.90),
                      t.canvasGradient[1].withValues(alpha: 0),
                    ],
                    stops: const [0, 0.80, 1],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Feed Shielding Engine',
                                style: context.type.headlineMedium?.copyWith(
                                  fontSize: 24,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Surgically remove addictive feeds',
                                style: context.type.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        GlassPanel(
                          radius: Radii.pill,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.md,
                            vertical: 6,
                          ),
                          accent: t.success,
                          glowStrength: 0.5,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.success,
                                  boxShadow: [
                                    BoxShadow(
                                      color: t.success.withValues(alpha: 0.8),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Active',
                                style: context.type.labelSmall?.copyWith(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
                    SegmentedControl(
                      options: const ['Feed Blocker', 'Whitelist', 'Profiles'],
                      index: _segment,
                      onChanged: (i) => setState(() => _segment = i),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feed Blocker
// ---------------------------------------------------------------------------

class _FeedBlockerView extends StatefulWidget {
  const _FeedBlockerView();

  @override
  State<_FeedBlockerView> createState() => _FeedBlockerViewState();
}

class _FeedBlockerViewState extends State<_FeedBlockerView> {
  late final List<List<bool>> _enabled = DemoData.feedGroups
      .map((g) => g.rows.map((r) => r.enabled).toList())
      .toList();
  late final List<List<int>> _modes = DemoData.feedGroups
      .map((g) => g.rows.map((r) => r.modeIndex).toList())
      .toList();

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < DemoData.feedGroups.length; g++) ...[
          if (g > 0) const SizedBox(height: Gap.xl),
          SectionHeader(
            title: DemoData.feedGroups[g].title,
            icon: DemoData.feedGroups[g].icon,
          ),
          GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              children: [
                for (var r = 0;
                    r < DemoData.feedGroups[g].rows.length;
                    r++) ...[
                  if (r > 0) ...[
                    Divider(color: t.hairline, height: Gap.xl),
                  ],
                  _FeedRowTile(
                    row: DemoData.feedGroups[g].rows[r],
                    enabled: _enabled[g][r],
                    modeIndex: _modes[g][r],
                    onToggle: (v) => setState(() => _enabled[g][r] = v),
                    onMode: (m) => setState(() => _modes[g][r] = m),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.xl),
        GlassPanel(
          radius: Radii.item,
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Icon(Icons.lock_rounded, size: 15, color: t.textTertiary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'Changes take effect immediately via the background service',
                  style: context.type.labelSmall?.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedRowTile extends StatelessWidget {
  const _FeedRowTile({
    required this.row,
    required this.enabled,
    required this.modeIndex,
    required this.onToggle,
    required this.onMode,
  });

  final FeedRow row;
  final bool enabled;
  final int modeIndex;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onMode;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassIconBadge(
              icon: row.icon,
              color: row.color,
              glow: enabled ? 0.55 : 0,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.title,
                          style: context.type.titleSmall,
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.success,
                            boxShadow: [
                              BoxShadow(
                                color: t.success.withValues(alpha: 0.75),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.description,
                    style: context.type.bodySmall?.copyWith(
                      color: t.textTertiary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            GlassToggle(
              value: enabled,
              onChanged: onToggle,
              accent: row.color,
            ),
          ],
        ),
        if (row.modes != null && enabled) ...[
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (var i = 0; i < row.modes!.length; i++)
                GlassPill(
                  selected: i == modeIndex,
                  accent: row.color,
                  onTap: () => onMode(i),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: 7,
                  ),
                  child: Text(
                    row.modes![i],
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Whitelist
// ---------------------------------------------------------------------------

class _WhitelistView extends StatefulWidget {
  const _WhitelistView();

  @override
  State<_WhitelistView> createState() => _WhitelistViewState();
}

class _WhitelistViewState extends State<_WhitelistView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          level: 2,
          radius: Radii.pill,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: t.textTertiary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: TextField(
                  controller: _search,
                  style: context.type.bodyLarge?.copyWith(fontSize: 15),
                  cursorColor: t.accentPrimary,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search installed apps…',
                    hintStyle: context.type.bodyMedium?.copyWith(
                      color: t.textTertiary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        const _WhitelistSection(
          title: 'Always Allowed',
          accent: Color(0xFF8FE39B),
          entries: DemoData.alwaysAllowed,
          showRemove: true,
        ),
        const SizedBox(height: Gap.xl),
        const _WhitelistSection(
          title: 'Time-Budgeted',
          accent: Color(0xFF7FA9FF),
          entries: DemoData.budgeted,
          showBudget: true,
        ),
        const SizedBox(height: Gap.xl),
        const _WhitelistSection(
          title: 'Blocked',
          accent: Color(0xFFFFB4AB),
          entries: DemoData.blockedApps,
        ),
      ],
    );
  }
}

class _WhitelistSection extends StatelessWidget {
  const _WhitelistSection({
    required this.title,
    required this.accent,
    required this.entries,
    this.showBudget = false,
    this.showRemove = false,
  });

  final String title;
  final Color accent;
  final List<WhitelistEntry> entries;
  final bool showBudget;
  final bool showRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Gap.md),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                title,
                style: context.type.labelMedium?.copyWith(
                  color: t.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length}',
                style: context.type.labelSmall?.copyWith(
                  color: t.textTertiary,
                ),
              ),
            ],
          ),
        ),
        GlassPanel(
          radius: Radii.card,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.xs,
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(color: t.hairline, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: _WhitelistRow(
                    entry: entries[i],
                    accent: accent,
                    showBudget: showBudget,
                    showRemove: showRemove,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WhitelistRow extends StatelessWidget {
  const _WhitelistRow({
    required this.entry,
    required this.accent,
    required this.showBudget,
    required this.showRemove,
  });

  final WhitelistEntry entry;
  final Color accent;
  final bool showBudget;
  final bool showRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlassIconBadge(
              icon: entry.icon,
              color: entry.color,
              size: 36,
              radius: 11,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(entry.name, style: context.type.titleSmall),
            ),
            if (showBudget && entry.budgeted)
              Text(
                'Daily budget: ${entry.budgetMinutes}m',
                style: context.type.labelSmall?.copyWith(
                  color: t.textTertiary,
                ),
              ),
            if (showRemove)
              Pressable(
                scale: 0.85,
                onTap: () {},
                child: Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: t.textTertiary,
                ),
              ),
            if (!showBudget && !showRemove)
              Icon(
                Icons.drag_indicator_rounded,
                size: 18,
                color: t.textTertiary,
              ),
          ],
        ),
        if (showBudget && entry.budgeted) ...[
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accent,
                    thumbColor: accent,
                  ),
                  child: Slider(
                    value: entry.budgetMinutes!.toDouble(),
                    max: 120,
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                '${entry.usedMinutes}m used',
                style: context.type.labelSmall?.copyWith(
                  color: entry.usage > 0.8 ? t.danger : t.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profiles
// ---------------------------------------------------------------------------

class _ProfilesView extends StatefulWidget {
  const _ProfilesView();

  @override
  State<_ProfilesView> createState() => _ProfilesViewState();
}

class _ProfilesViewState extends State<_ProfilesView> {
  int _active = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Restriction profiles',
          icon: Icons.tune_rounded,
        ),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 2),
            itemCount: DemoData.profiles.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
            itemBuilder: (context, i) {
              if (i == DemoData.profiles.length) return const _AddProfileCard();
              final p = DemoData.profiles[i];
              return _ProfileCard(
                profile: p,
                active: i == _active,
                onActivate: () => setState(() => _active = i),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.xl),
        const SectionHeader(
          title: 'Scheduled strictness',
          icon: Icons.schedule_rounded,
        ),
        GlassPanel(
          radius: Radii.card,
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            children: [
              _ScheduleRow(
                label: 'Weekdays',
                detail: '07:00 – 09:00',
                color: t.accentPrimary,
              ),
              Divider(color: t.hairline, height: Gap.xl),
              _ScheduleRow(
                label: 'Evening block',
                detail: '20:00 – 22:30',
                color: t.accentSecondary,
              ),
              Divider(color: t.hairline, height: Gap.xl),
              _ScheduleRow(
                label: 'Exam week override',
                detail: 'All day',
                color: t.danger,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onActivate,
  });

  final RestrictionProfile profile;
  final bool active;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return SizedBox(
      width: 196,
      child: GlassPanel(
        radius: Radii.card,
        padding: const EdgeInsets.all(Gap.lg),
        accent: active ? t.accentPrimary : null,
        glowStrength: active ? 0.8 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassIconBadge(
                  icon: profile.icon,
                  color: active ? t.accentPrimary : t.textTertiary,
                  size: 34,
                  radius: 10,
                  glow: active ? 0.6 : 0,
                ),
                const Spacer(),
                if (active)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: t.accentPrimary,
                  ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(profile.name, style: context.type.titleSmall),
            const SizedBox(height: 3),
            Text(
              '${profile.blockedApps} apps blocked',
              style: context.type.labelSmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${profile.dailyTargetHours}h daily target',
              style: context.type.labelSmall,
            ),
            const Spacer(),
            GlassPill(
              selected: active,
              onTap: onActivate,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 7,
              ),
              child: Text(
                active ? 'Active' : 'Activate',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard();

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return SizedBox(
      width: 132,
      child: Pressable(
        onTap: () {},
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(
              color: t.glassL2Border,
              style: BorderStyle.solid,
            ),
            color: t.glassL1Fill,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 26, color: t.textTertiary),
              const SizedBox(height: Gap.sm),
              Text('New profile', style: context.type.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(child: Text(label, style: context.type.bodyLarge)),
        Text(
          detail,
          style: context.type.labelMedium?.copyWith(color: t.textTertiary),
        ),
      ],
    );
  }
}
