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
                "{0}FocusForge uses Android Accessibility only for optional YouTube screen filters. It checks YouTube screen identifiers to tell Shorts and supported feeds from ordinary videos. These screen checks stay on your device and are not stored or sent to a server. It does not read messages, passwords or text you type.\n\nWhile a YouTube pause is visible, it checks application window package names so the pause closes when you leave YouTube; it does not inspect other apps’ contents.\n\nNormal app boundaries use Usage access and Draw over other apps. They work without Accessibility.\n\nYour chosen app names, pause decisions and their times are saved only on this device for Shield insights.\n\nThis access is optional. You can turn it off in Android Settings at any time. The focus timer works without it.\n\nIn Android Settings, choose FocusForge under Accessibility and enable its service. Return here and turn on your chosen rule.",
                const [''],
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
