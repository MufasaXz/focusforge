import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/community_providers.dart';

Future<bool> confirmCommunityTerms(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("Keep the study community respectful")),
        scrollable: true,
        content: Text(
          context.tr(
            "Before sharing a name or joining a group, agree to these rules: no harassment, threats, hate, sexual content, impersonation or sharing private information. Use an appropriate display name and invite only people you trust. You can report content and hide a member from their menu. Reports are reviewed by the developer and may lead to content removal or account restrictions.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("Accept and continue")),
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
      title: Text(context.tr("Report content")),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr(
              "Report {0} privately to the developer. Do not include passwords or sensitive personal details.",
              [name],
            ),
          ),
          TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr("Reason for report"),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(context.tr("Continue")),
        ),
      ],
    ),
  );
  controller.dispose();
  if (reason == null || reason.isEmpty || !context.mounted) return;
  final body = context.tr(
    "Account: {0}\nDisplayed name: {1}\nGroup: {2}\nReason: {3}",
    [uid, name, groupId ?? 'weekly leaderboard', reason],
  );
  final uri = Uri(
    scheme: 'mailto',
    path: 'sudeepyadav7272@gmail.com',
    query: context.tr("subject={0}&body={1}", [
      Uri.encodeComponent('FocusForge community report'),
      Uri.encodeComponent(body),
    ]),
  );
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("Send your report by email")),
        content: Text(
          context.tr(
            "Email sudeepyadav7272@gmail.com with the displayed name, group and reason. No report has been sent yet.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr("OK")),
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
    tooltip: context.tr("Report or hide {0}", [name]),
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
            SnackBar(
              content: Text(
                context.tr(
                  "Member hidden on this account. Their rows will no longer appear.",
                ),
              ),
            ),
          );
        }
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'report', child: Text(context.tr("Report content"))),
      PopupMenuItem(value: 'hide', child: Text(context.tr("Hide member"))),
    ],
  );
}
