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
        ? 'View timer'
        : started
        ? 'Resume'
        : timer.phase.isBreak
        ? 'Start break'
        : 'Start focus';
    final detail = started
        ? '${timer.phase.label} · ${formatClock(timer.remaining)} ${timer.running ? 'left' : 'paused'}'
        : timer.phase.isBreak
        ? '${timer.phase.label} · ${formatMinutes(timer.remaining.inMinutes)}'
        : '${formatMinutes(timer.plannedDuration(preset).inMinutes)} focus · ${preset.shortBreak}m break';

    void open() {
      if (!timer.running) ref.read(timerProvider.notifier).start();
      onOpen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject?.name ?? preset.name,
              style: tt.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Gap.xs),
            Text(
              detail,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
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
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        );
        // Give enlarged text its own line instead of squeezing the action out.
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
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
