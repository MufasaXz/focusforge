import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/icon_badge.dart';

/// This week's leading subject, as one row.
///
/// A row rather than a chart: the breakdown beside it already carries the
/// split, and the question this answers — "what have I actually been studying"
/// — is a single name. Nothing here opens anything, so it carries no chevron;
/// an arrow that leads nowhere is a promise the row cannot keep.
class TopSubjectCard extends ConsumerWidget {
  const TopSubjectCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final top = ref.watch(topSubjectProvider);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: top == null
            ? Row(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      'Nothing logged this week yet — finish a session and '
                      'your leading subject lands here.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              )
            : Semantics(
                label:
                    'Top subject this week: ${top.name}, '
                    '${spokenHours(top.minutes / 60)} across '
                    '${top.sessions} ${top.sessions == 1 ? 'session' : 'sessions'}',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      IconBadge(
                        icon: top.icon,
                        color: top.color,
                        size: 44,
                        radius: 13,
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              top.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatMinutes(top.minutes)}  •  '
                              '${top.sessions} '
                              '${top.sessions == 1 ? 'session' : 'sessions'}',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
