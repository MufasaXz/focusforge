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
          'FocusForge uses Android accessibility access to detect the app in '
          'the foreground and show a pause screen for apps you choose to shield.\n\n'
          'For YouTube filters, it also checks YouTube screen identifiers to '
          'tell Shorts from ordinary videos. These screen checks stay on your '
          'device and are not stored or sent to a server. It does not read '
          'messages, passwords or text you type.\n\n'
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
