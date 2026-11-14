import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/chat/cloud_consent_dialog.dart';

void main() {
  testWidgets(
    'consent choices remain equally sized and readable on a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await showPipCloudConsent(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final choices = find.byType(OutlinedButton);
      expect(choices, findsNWidgets(2));
      expect(tester.getSize(choices.first), tester.getSize(choices.last));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Disagree (Offline Mode)'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
}
