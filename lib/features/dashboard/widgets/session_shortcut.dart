import '../../../core/localization/display_labels.dart';
import '../../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';

/// A way back into studying, even once Home has a log to show.
class SessionShortcut extends ConsumerWidget {
  const SessionShortcut({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final timer = ref.watch(timerProvider);
    final preset = ref.watch(presetsProvider)[timer.presetIndex];
    final subject = ref
        .watch(subjectsProvider)
        .where((s) => s.id == timer.subjectId)
        .firstOrNull;
    final started =
        timer.running || timer.remaining < timer.plannedDuration(preset);
    final label = timer.running
        ? context.tr("View timer")
        : started
        ? context.tr("Resume")
        : timer.phase.isBreak
        ? context.tr("Start break")
        : context.tr("Start focus");
    final detail = timer.hidesDuration(preset)
        ? context.tr("Time stays hidden")
        : started
        ? context.tr('{0} · {1} {2}', [
            context.tr(timer.phase.label),
            formatClock(timer.remaining),
            context.tr(timer.running ? 'left' : 'paused'),
          ])
        : timer.phase.isBreak
        ? context.tr('{0} · {1}', [
            context.tr(timer.phase.label),
            formatMinutes(timer.remaining.inMinutes),
          ])
        : context.tr("{0} focus · {1}m break", [
            formatMinutes(timer.plannedDuration(preset).inMinutes),
            preset.shortBreak,
          ]);

    void open() {
      if (!timer.running) ref.read(timerProvider.notifier).start();
      onOpen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final detailStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
        final actionStyle =
            Theme.of(context).filledButtonTheme.style?.textStyle?.resolve({}) ??
            tt.labelLarge;
        double textWidth(String value, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final actionWidth =
            (textWidth(label, actionStyle) + 18 + Gap.sm + Gap.lg * 2).clamp(
              144.0,
              double.infinity,
            );
        final rowWidth = actionWidth + Gap.md + textWidth(detail, detailStyle);
        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject?.name ?? presetDisplayName(context, preset),
              style: tt.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Gap.xs),
            Text(detail, style: detailStyle),
          ],
        );
        final button = FilledButton.icon(
          onPressed: open,
          icon: Icon(
            timer.running
                ? Icons.arrow_forward_rounded
                : Icons.play_arrow_rounded,
            size: 18,
          ),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size(144, 48),
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            shape: const StadiumBorder(),
          ),
        );
        // A normal phone has about 310dp inside the goal card. Keep the
        // reference row there, while allowing longer translations or larger
        // text to use their own lines before either label gets squeezed.
        if (constraints.maxWidth < 280 ||
            constraints.maxWidth < rowWidth ||
            textScaler.scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: Gap.md),
              button,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: Gap.md),
            button,
          ],
        );
      },
    );
  }
}
