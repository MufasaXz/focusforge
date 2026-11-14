import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';

/// Cloud use is optional. Closing the dialog grants no permission.
Future<bool?> showPipCloudConsent(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.tr('Enable Cloud Study Coach?')),
    content: SingleChildScrollView(
      child: Text(
        context.tr(
          'Pip can use cloud intelligence to give you personalized study schedules, exam prep tips, and focus coaching. Only study totals and redacted questions and recent messages are sent for coaching. Your app lists stay on your device. Redaction may miss personal details, so leave them out of questions. You can switch modes anytime in Settings.',
        ),
      ),
    ),
    actions: [
      SizedBox(
        width: double.maxFinite,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final choice in [false, true]) ...[
                if (choice) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 72),
                      padding: const EdgeInsets.all(8),
                    ),
                    onPressed: () => Navigator.of(context).pop(choice),
                    child: Text(
                      context.tr(
                        choice ? 'Agree & Enable' : 'Disagree (Offline Mode)',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  ),
);
