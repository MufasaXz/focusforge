import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/shared/widgets/app_segmented_control.dart';

void main() {
  testWidgets(
    'choices remain reachable with large text, RTL and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(amoled: true),
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) => AppSegmentedControl<int>(
                      options: const {0: 'Light', 1: 'System', 2: 'Dark'},
                      selected: selected,
                      onChanged: (value) => setState(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final label in ['Light', 'System', 'Dark']) {
          final button = find.widgetWithText(TextButton, label);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.text('Dark'));
        await tester.pump();
        expect(selected, 2);
        expect(
          tester.getSemantics(find.widgetWithText(TextButton, 'Dark')),
          matchesSemantics(
            label: 'Dark',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final indicator = tester.widget<AnimatedAlign>(
          find.byType(AnimatedAlign),
        );
        expect(indicator.duration, Duration.zero);
        expect(indicator.alignment, AlignmentDirectional.centerEnd);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
