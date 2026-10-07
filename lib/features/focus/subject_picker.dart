import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/study_providers.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/pressable.dart';
import 'subject_sheet.dart';

/// What the next finished block will be logged against.
///
/// The selection is the timer's own state rather than local to this widget, so
/// the chip and the session the engine writes cannot disagree: there is one
/// value, and both read it. Nothing here is required — a session with no
/// subject is still counted, it just has no row in the day's breakdown.
///
/// The row is the whole device's worth of subjects plus the chip that adds
/// one, so it scrolls horizontally rather than wrapping: a second line of
/// chips would push the timer down the page every time a subject was added.
class SubjectPicker extends ConsumerWidget {
  const SubjectPicker({super.key, required this.accent});

  /// The live phase colour, so the selected chip matches the timer beside it.
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subjects = ref.watch(subjectsProvider);
    final selectedId = ref.watch(timerProvider).subjectId;
    final selected = subjects.where((s) => s.id == selectedId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Studying',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.0,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: Gap.sm),
            // What the engine will write, said in words. The chip below shows
            // it too, but a chip scrolled out of view cannot.
            Expanded(
              child: Text(
                selected == null ? 'Not tagged' : selected.name,
                style: tt.labelSmall?.copyWith(
                  fontSize: 11.5,
                  color: selected == null
                      ? cs.onSurfaceVariant
                      : selected.color,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected != null)
              _ClearTag(
                onTap: () => ref.read(timerProvider.notifier).setSubject(null),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs + 2),
        EdgeFade(
          trailing: 28,
          child: SizedBox(
            // Deliberately short. The chips are a tag row under the timer, not
            // a second control competing with it: every dp they take is a dp
            // the ring loses, and the ring is the thing being looked at.
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // One chip per subject, then the add chip.
              itemCount: subjects.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
              itemBuilder: (context, i) {
                if (i == subjects.length) {
                  return _AddChip(
                    onTap: () => _add(context, ref),
                    label: subjects.isEmpty ? 'Add a subject' : 'New',
                  );
                }
                final subject = subjects[i];
                return _SubjectChip(
                  subject: subject,
                  selected: subject.id == selectedId,
                  accent: accent,
                  onTap: () => ref
                      .read(timerProvider.notifier)
                      .setSubject(subject.id == selectedId ? null : subject.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Creates a subject and tags the running session with it.
  ///
  /// Selecting what was just made is the whole point of adding it from here:
  /// the user is about to study it, and a subject that arrives unselected
  /// would have to be tapped before the session it was created for.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final subject = await showSubjectSheet(context);
    if (subject == null) return;
    ref.read(timerProvider.notifier).setSubject(subject.id);
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.subject,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Subject subject;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label:
          'Subject ${subject.name}, '
          '${selected ? 'selected' : 'not selected'}',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            color: selected
                ? subject.color.withValues(alpha: 0.20)
                : cs.surfaceContainer,
            border: Border.all(
              color: selected
                  ? subject.color.withValues(alpha: 0.75)
                  : cs.outlineVariant,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The dot is the subject's identity in every other view — the
              // breakdown, the day sheet — so it leads here too.
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: subject.color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                subject.name,
                style: tt.labelSmall?.copyWith(
                  fontSize: 11.5,
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (subject.minutesToday > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '${subject.minutesToday}m',
                  style: tt.labelSmall?.copyWith(
                    fontSize: 10,
                    color: selected
                        ? subject.color
                        : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The chip that opens the new-subject sheet. Deliberately not a subject
/// colour: it is an action, not a thing that can be selected.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Add a subject',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        child: DottedBorderBox(
          radius: Radii.pill,
          color: cs.outline,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 14, color: cs.primary),
                const SizedBox(width: Gap.xs + 1),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
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

/// A pill with a dashed outline — the conventional "this one is empty, put
/// something here" affordance, drawn rather than drawn from an asset.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.radius,
    required this.color,
  });

  final Widget child;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(radius: radius, color: color),
    child: child,
  );
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.radius != radius || old.color != color;
}

class _ClearTag extends StatelessWidget {
  const _ClearTag({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Clear the subject tag',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.xs,
          ),
          child: Text(
            'Clear',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
              decoration: TextDecoration.underline,
              decorationColor: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
