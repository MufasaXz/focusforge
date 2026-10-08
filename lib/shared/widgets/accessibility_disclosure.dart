import 'package:flutter/material.dart';

/// Explicit consent before handing the user to Android's accessibility page.
Future<bool> confirmShieldAccess(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('How Shield uses accessibility'),
        scrollable: true,
        content: const Text(
          'FocusForge uses Android accessibility access to detect the app in '
          'the foreground and show a pause screen for apps you choose to shield.\n\n'
          'For YouTube filters, it also checks YouTube screen identifiers to '
          'tell Shorts from ordinary videos. These screen checks stay on your '
          'device and are not stored or sent to a server. It does not read '
          'messages, passwords or text you type.\n\n'
          'This access is optional. You can turn it off in Android Settings '
          'at any time. The focus timer works without it.',
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
