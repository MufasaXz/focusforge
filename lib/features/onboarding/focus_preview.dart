import 'package:flutter/material.dart';

import '../focus/widgets/clock_faces.dart';

/// An illustration of a focus block, excluded from live-timer semantics.
class FocusPreview extends StatelessWidget {
  const FocusPreview({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: MediaQuery.withNoTextScaling(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: RetroClock(
            remaining: const Duration(minutes: 25),
            accent: Theme.of(context).colorScheme.primary,
            size: 172,
            progress: 0,
          ),
        ),
      ),
    ),
  );
}
