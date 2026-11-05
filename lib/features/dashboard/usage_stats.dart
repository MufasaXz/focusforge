import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/usage_stats_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/glass_surface.dart';

/// Fixed colours for the three groups, so a bar reads the same in either
/// theme and on every screen.
Color usageColor(UsageCategory category, ColorScheme cs) => switch (category) {
  UsageCategory.distracting => const Color(0xFFFF8A1F),
  UsageCategory.productive => const Color(0xFF63C35A),
  UsageCategory.other =>
    cs.brightness == Brightness.dark
        ? const Color(0xFF8C8C8C)
        : const Color(0xFFA9A9A9),
};

String usageLabel(UsageCategory category) => switch (category) {
  UsageCategory.distracting => 'Distracting',
  UsageCategory.productive => 'Productive',
  UsageCategory.other => 'Others',
};

/// Seven bars, Monday to Sunday, each split by category.
///
/// With [selected] set (the daily view) the chosen day is drawn in colour and
/// the others in one muted tone, so the day reads against its week; without
/// it every day is in colour. [only] narrows the bars to one category.
class UsageWeekChart extends StatelessWidget {
  const UsageWeekChart({
    super.key,
    required this.week,
    required this.classifier,
    this.selected,
    this.only,
    this.onDayTap,
    this.height = 150,
  });

  final List<Map<String, int>> week;
  final UsageClassifier classifier;
  final int? selected;
  final UsageCategory? only;
  final ValueChanged<int>? onDayTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final splits = [for (final day in week) classifier.split(day)];
    int totalOf(Map<UsageCategory, int> split) =>
        only == null ? split.values.fold(0, (a, b) => a + b) : split[only]!;
    final busiest = splits.map(totalOf).fold(0, (a, b) => a > b ? a : b);
    // The scale rounds up to whole even hours, two at least.
    final topHours = ((busiest / 60).ceil() + 1) ~/ 2 * 2;
    final top = (topHours < 2 ? 2 : topHours) * 60;
    final muted = cs.onSurfaceVariant.withValues(alpha: .22);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    // The phone's own weekday letters, Monday first.
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    final letters = [for (var i = 0; i < 7; i++) narrow[(i + 1) % 7]];

    return SizedBox(
      height: height + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${top ~/ 60}h', style: labelStyle),
                Text('${top ~/ 120}h', style: labelStyle),
                Text('0h', style: labelStyle),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                for (final fraction in const [0.0, 0.5, 1.0])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: height * fraction,
                    child: Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Semantics(
                          button: onDayTap != null,
                          selected: selected == i,
                          label: [
                            letters[i],
                            formatMinutes(
                              i < splits.length ? totalOf(splits[i]) : 0,
                            ),
                          ].join(', '),
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onDayTap == null ? null : () => onDayTap!(i),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: height,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: _Bar(
                                      split: i < splits.length
                                          ? splits[i]
                                          : null,
                                      only: only,
                                      top: top,
                                      height: height,
                                      muted: selected != null && selected != i
                                          ? muted
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  letters[i],
                                  style: labelStyle?.copyWith(
                                    color: selected == i ? cs.onSurface : null,
                                    fontWeight: selected == i
                                        ? FontWeight.w700
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.split,
    required this.only,
    required this.top,
    required this.height,
    this.muted,
  });

  final Map<UsageCategory, int>? split;
  final UsageCategory? only;
  final int top;
  final double height;
  final Color? muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parts = [
      for (final category in const [
        UsageCategory.other,
        UsageCategory.productive,
        UsageCategory.distracting,
      ])
        if (only == null || only == category) (category, split?[category] ?? 0),
    ];
    final total = parts.fold(0, (sum, part) => sum + part.$2);
    if (total == 0) return const SizedBox(width: 22);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: SizedBox(
        width: 22,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (category, minutes) in parts)
              if (minutes > 0)
                Container(
                  height: (height * minutes / top).clamp(1.5, height),
                  color: muted ?? usageColor(category, cs),
                ),
          ],
        ),
      ),
    );
  }
}

/// Three totals with their colour dots.
class UsageLegend extends StatelessWidget {
  const UsageLegend({super.key, required this.split});

  final Map<UsageCategory, int> split;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        for (final category in UsageCategory.values)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: usageColor(category, cs),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatMinutes(split[category] ?? 0),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        context.tr(usageLabel(category)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Today's screen time on Home: the total, this week's bars and the split,
/// opening the full stats.
class ScreenTimeOverview extends ConsumerWidget {
  const ScreenTimeOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final week = ref.watch(weekUsageProvider(weekStart(now)));
    final classifier = ref.watch(usageClassifierProvider);
    final todayIndex = now.weekday - DateTime.monday;

    void open([int? day]) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UsageStatsScreen(
          initialDay: day == null
              ? null
              : addDays(weekStart(now), day),
        ),
      ),
    );

    // Straight on the page rather than in a card: the section header above
    // already groups it, and a box around a chart only shrinks it.
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: week.when(
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) =>
              Text(context.tr("Screen time could not be read right now.")),
          data: (days) {
            final today = days.length > todayIndex
                ? days[todayIndex]
                : const <String, int>{};
            final split = classifier.split(today);
            final total = split.values.fold(0, (a, b) => a + b);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMinutes(total),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                          Text(
                            context.tr("Screen time today"),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: open,
                      child: Text(context.tr("See all")),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                UsageWeekChart(
                  week: days,
                  classifier: classifier,
                  selected: todayIndex,
                  height: 110,
                  onDayTap: open,
                ),
                const SizedBox(height: Gap.md),
                UsageLegend(split: split),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Daily and weekly screen time, by app, on this phone.
class UsageStatsScreen extends ConsumerStatefulWidget {
  const UsageStatsScreen({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  ConsumerState<UsageStatsScreen> createState() => _UsageStatsScreenState();
}

class _UsageStatsScreenState extends ConsumerState<UsageStatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
  late DateTime _day = dayStart(widget.initialDay ?? DateTime.now());
  UsageCategory? _only;
  final _search = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _weekly => _tabs.index == 1;

  DateTime get _today => dayStart(DateTime.now());

  bool get _canGoForward => _weekly
      ? weekStart(_day).isBefore(weekStart(_today))
      : _day.isBefore(_today);

  void _move(int direction) {
    setState(() {
      _day = addDays(_day, direction * (_weekly ? 7 : 1));
      if (_day.isAfter(_today)) _day = _today;
    });
  }

  String _dateLabel(BuildContext context) {
    String short(DateTime d) =>
        MaterialLocalizations.of(context).formatShortMonthDay(d);
    if (_weekly) {
      final start = weekStart(_day);
      final end = addDays(start, 6);
      return '${short(start)} – ${short(end)}';
    }
    final full = MaterialLocalizations.of(context).formatMediumDate(_day);
    if (_day == _today) return context.tr("Today · {0}", [full]);
    return full;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final monday = weekStart(_day);
    final week = ref.watch(weekUsageProvider(monday));
    final previous = _weekly
        ? ref.watch(weekUsageProvider(addDays(monday, -7)))
        : null;
    final classifier = ref.watch(usageClassifierProvider);
    final query = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("Usage stats")),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr("Daily")),
            Tab(text: context.tr("Weekly")),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshUsage(ref);
          await ref.read(weekUsageProvider(monday).future);
        },
        child: week.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(context.tr("Screen time could not be read right now.")),
          ),
          data: (days) {
            final index = _day.difference(monday).inDays.clamp(0, 6);
            // Minutes per app for the shown span.
            final span = <String, int>{};
            for (final (i, day) in days.indexed) {
              if (!_weekly && i != index) continue;
              for (final entry in classifier.select(day).entries) {
                span[entry.key] = (span[entry.key] ?? 0) + entry.value;
              }
            }
            final split = classifier.split(span);
            final shown = _only == null
                ? split.values.fold(0, (a, b) => a + b)
                : split[_only]!;
            final daysCounted = _weekly
                ? days.where((d) => classifier.select(d).isNotEmpty).length
                : 1;
            int? change;
            final before = previous?.valueOrNull;
            if (_weekly && before != null) {
              final last = before
                  .map((d) => classifier.select(d, _only))
                  .fold(0, (sum, d) => sum + d.values.fold(0, (a, b) => a + b));
              if (last > 0) change = ((shown - last) * 100 / last).round();
            }
            final rows =
                classifier
                    .select(span, _only)
                    .entries
                    .where(
                      (e) =>
                          query.isEmpty ||
                          classifier
                              .nameOf(e.key)
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.lg,
                Gap.xl,
                Gap.xxl,
              ),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in <UsageCategory?>[
                        null,
                        ...UsageCategory.values,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: Gap.sm),
                          child: ChoiceChip(
                            label: Text(
                              category == null
                                  ? context.tr("All apps")
                                  : context.tr(usageLabel(category)),
                            ),
                            selected: _only == category,
                            onSelected: (_) => setState(() => _only = category),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xl),
                Row(
                  children: [
                    IconButton(
                      tooltip: context.tr("Earlier"),
                      onPressed: () => _move(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            formatMinutes(shown),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            _dateLabel(context),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr("Later"),
                      onPressed: _canGoForward ? () => _move(1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                if (change != null) ...[
                  const SizedBox(height: Gap.md),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Radii.tile),
                      ),
                      child: Text(
                        change <= 0
                            ? context.tr("{0}% less than last week", [-change])
                            : context.tr("{0}% more than last week", [change]),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Gap.xl),
                UsageWeekChart(
                  week: days,
                  classifier: classifier,
                  selected: _weekly ? null : index,
                  only: _only,
                  height: 170,
                  onDayTap: _weekly
                      ? null
                      : (i) {
                          final day = addDays(monday, i);
                          if (!day.isAfter(_today)) setState(() => _day = day);
                        },
                ),
                const SizedBox(height: Gap.lg),
                UsageLegend(split: split),
                const SizedBox(height: Gap.xl),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: context.tr("Search apps"),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.card),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                    child: Text(
                      context.tr("No app use recorded for this time."),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ContentCard(
                    child: Column(
                      children: [
                        for (final (i, row) in rows.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          _AppUsageRow(
                            onTap: () => _chooseCategory(
                              context,
                              ref,
                              row.key,
                              classifier.nameOf(row.key),
                            ),
                            packageId: row.key,
                            name: classifier.nameOf(row.key),
                            category: classifier.categoryOf(row.key),
                            minutes: _weekly && daysCounted > 0
                                ? (row.value / daysCounted).round()
                                : row.value,
                            average: _weekly,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Lets the user put an app in a group of their own choosing, or hand it back
/// to the automatic grouping.
Future<void> _chooseCategory(
  BuildContext context,
  WidgetRef ref,
  String packageId,
  String name,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final chosen = ref.watch(usageCategoryOverridesProvider)[packageId];
      Future<void> pick(UsageCategory? category) async {
        await ref
            .read(usageCategoryOverridesProvider.notifier)
            .set(packageId, category);
        if (context.mounted) Navigator.pop(context);
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr("Group {0} as", [name]),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              context.tr(
                "Your choice is kept on this phone and used in every chart.",
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.lg),
            for (final category in UsageCategory.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: usageColor(category, cs),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(context.tr(usageLabel(category))),
                trailing: chosen == category
                    ? Icon(Icons.check_rounded, color: cs.primary)
                    : null,
                onTap: () => pick(category),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(context.tr("Automatic")),
              subtitle: Text(
                context.tr("Grouped by Shield rules and the app's type"),
              ),
              trailing: chosen == null
                  ? Icon(Icons.check_rounded, color: cs.primary)
                  : null,
              onTap: () => pick(null),
            ),
          ],
        ),
      );
    },
  ),
);

class _AppUsageRow extends StatelessWidget {
  const _AppUsageRow({
    required this.onTap,
    required this.packageId,
    required this.name,
    required this.category,
    required this.minutes,
    required this.average,
  });

  final String packageId;
  final String name;
  final UsageCategory category;
  final int minutes;
  final bool average;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = usageColor(category, cs);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            AppIconAvatar(
              packageId: packageId,
              fallbackIcon: Icons.apps_rounded,
              fallbackColor: color,
              size: 44,
              radius: 22,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Text(
                        context.tr(usageLabel(category)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: category == UsageCategory.other
                              ? cs.onSurfaceVariant
                              : color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              average
                  ? context.tr("{0} a day", [formatMinutes(minutes)])
                  : formatMinutes(minutes),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
