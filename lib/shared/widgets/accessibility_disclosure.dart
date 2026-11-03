import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';

/// Explicit consent before handing the user to Android's accessibility page.
Future<bool> confirmShieldAccess(
  BuildContext context, {
  String? feature,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: Text(
          feature == null
              ? context.tr("How Shield uses accessibility")
              : context.tr("Allow {0}", [feature]),
        ),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(
                "FocusForge uses Accessibility only for its optional YouTube filters, and only while one is on. Shorts and feed filters check YouTube’s screen identifiers to tell those screens from ordinary videos. Study mode also reads the channel name and title of the video you open, to compare them with your study channels and subjects. These checks stay on your device and nothing they read is saved or uploaded. While a pause is showing, FocusForge checks only which app is in front, so the pause closes when you leave. It never reads messages, passwords or what you type. Access is optional and can be turned off in Android Settings at any time.",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("Later")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("Agree and open Settings")),
          ),
        ],
      ),
    ) ??
    false;
