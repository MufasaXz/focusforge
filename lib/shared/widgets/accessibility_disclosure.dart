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
          feature == null ? 'How Shield uses accessibility' : 'Allow $feature',
        ),
        scrollable: true,
        content: Text(
          '${feature == null ? '' : 'To enable $feature, FocusForge needs Android Accessibility access. This rule stays off until access is allowed and you turn it on again.\n\n'}'
          'FocusForge uses Android Accessibility only for optional YouTube screen filters. '
          'It checks YouTube screen identifiers to tell Shorts and supported feeds '
          'from ordinary videos. These screen checks stay on your device and are '
          'not stored or sent to a server. It does not read messages, passwords or text you type.\n\n'
          'While a YouTube pause is visible, it checks application window package names '
          'so the pause closes when you leave YouTube; it does not inspect other apps’ contents.\n\n'
          'Normal app boundaries use Usage access and Draw over other apps. '
          'They work without Accessibility.\n\n'
          'Your chosen app names, pause decisions and their times are saved '
          'only on this device for Shield insights.\n\n'
          'This access is optional. You can turn it off in Android Settings '
          'at any time. The focus timer works without it.\n\n'
          'In Android Settings, choose FocusForge under Accessibility and enable '
          'its service. Return here and turn on your chosen rule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and open Settings'),
          ),
        ],
      ),
    ) ??
    false;
