import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/community_providers.dart';

Future<bool> confirmCommunityTerms(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep the study community respectful'),
        scrollable: true,
        content: const Text(
          'Before sharing a name or joining a group, agree to these rules: '
          'no harassment, threats, hate, sexual content, impersonation or sharing private information. '
          'Use an appropriate display name and invite only people you trust. '
          'You can report content and hide a member from their menu. '
          'Reports are reviewed by the developer and may lead to content removal or account restrictions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept and continue'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> reportCommunityContent(
  BuildContext context, {
  required String uid,
  required String name,
  String? groupId,
}) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Report content'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Report $name privately to the developer. Do not include passwords or sensitive personal details.',
          ),
          TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason for report'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (reason == null || reason.isEmpty || !context.mounted) return;
  final body =
      'Account: $uid\nDisplayed name: $name\nGroup: ${groupId ?? 'weekly leaderboard'}\nReason: $reason';
  final uri = Uri(
    scheme: 'mailto',
    path: 'sudeepyadav7272@gmail.com',
    query:
        'subject=${Uri.encodeComponent('FocusForge community report')}&body=${Uri.encodeComponent(body)}',
  );
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send your report by email'),
        content: const Text(
          'Email sudeepyadav7272@gmail.com with the displayed name, group and reason. No report has been sent yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class CommunityMemberMenu extends ConsumerWidget {
  const CommunityMemberMenu({
    super.key,
    required this.uid,
    required this.name,
    this.groupId,
  });
  final String uid, name;
  final String? groupId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Report or hide $name',
    onSelected: (action) async {
      if (action == 'report') {
        await reportCommunityContent(
          context,
          uid: uid,
          name: name,
          groupId: groupId,
        );
      } else {
        await ref.read(blockedCommunityUsersProvider.notifier).block(uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Member hidden on this account. Their rows will no longer appear.',
              ),
            ),
          );
        }
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'report', child: Text('Report content')),
      PopupMenuItem(value: 'hide', child: Text('Hide member')),
    ],
  );
}
