import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/usage_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_icon_avatar.dart';
import '../../../shared/widgets/icon_badge.dart';

/// Today's real screen time, read from the platform.
///
/// This is the one card on the dashboard that is about the phone rather than
/// about study, and it is here because the two numbers belong side by side: a
/// day with four hours of focus and six hours of scrolling is a different day
/// from the same four hours and forty minutes.
///
/// It reads usage rather than the rule list, so it is useful before the user
/// has shielded anything — and it says plainly when Android will not answer,
/// instead of drawing an empty chart that reads as "nothing used today".
class ScreenTimeCard extends ConsumerWidget {
  const ScreenTimeCard({super.key, this.maxRows = 4});

  /// How many apps to name. The rest are folded into the total.
  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(usageAccessProvider);
    final screenTime = ref.watch(screenTimeTodayProvider);

    // Still reading the platform on the first frame. A spinner rather than a
    // skeleton: this card is small, and a card-sized skeleton would push the
    // sections below it down when it resolved.
    if (access.isLoading || screenTime.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Gap.xl),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    if (access.valueOrNull == false) {
      return const _Notice(
        icon: Icons.timelapse_rounded,
        body:
            'Android is not sharing app usage with FocusForge, so today\'s '
            'screen time cannot be read. Grant usage access from the Shield '
            'tab to see it here.',
      );
    }

    if (access.hasError || screenTime.hasError) {
      return const _Notice(
        icon: Icons.error_outline_rounded,
        body: 'The usage service did not answer. Pull down to try again.',
      );
    }

    final rows = screenTime.valueOrNull ?? const <ScreenTimeRow>[];
    if (rows.isEmpty) {
      return const _Notice(
        icon: Icons.hourglass_empty_rounded,
        body:
            'No app has been opened yet today. This fills in as the day goes '
            'on.',
      );
    }

    return _Rows(rows: rows, maxRows: maxRows);
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.maxRows});

  final List<ScreenTimeRow> rows;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = rows.take(maxRows).toList(growable: false);
    final total = rows.fold(0, (sum, row) => sum + row.minutes);
    final busiest = shown.first.minutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMinutes(total),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            const SizedBox(width: Gap.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'across ${rows.length} ${rows.length == 1 ? 'app' : 'apps'}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: Gap.md),
          _Row(row: shown[i], busiest: busiest),
        ],
        if (rows.length > shown.length) ...[
          const SizedBox(height: Gap.md),
          Text(
            'and ${rows.length - shown.length} more',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.busiest});

  final ScreenTimeRow row;
  final int busiest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final share = busiest == 0 ? 0.0 : row.minutes / busiest;

    return Semantics(
      label: '${row.name}, ${formatMinutes(row.minutes)} today',
      child: ExcludeSemantics(
        child: Row(
          children: [
            AppIconAvatar(
              packageId: row.packageId,
              fallbackIcon: Icons.android_rounded,
              fallbackColor: cs.primary,
              size: 34,
              radius: Radii.tile,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        formatMinutes(row.minutes),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: share,
                      color: cs.secondary,
                      backgroundColor: cs.surfaceContainerHighest,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.body});

  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(
          icon: icon,
          color: cs.onSurfaceVariant,
          size: 40,
          radius: Radii.tile,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              body,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}
