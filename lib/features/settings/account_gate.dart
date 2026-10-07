import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import 'settings_support.dart';

/// The one place that asks a local account to become a real one.
///
/// Two features need a real account — study groups, because they compare you
/// with other people, and the weekly board, because a row has to belong to
/// somebody. Both get the same gate: what the feature adds, and one tap that
/// links an account without losing anything already logged.
///
/// The gate is a first-class state rather than an error. An anonymous user
/// keeps every other feature in the app, and a screen that explained that
/// badly would read as the app withholding something.
class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({
    super.key,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    this.sectionTitle,
    this.items = const [],
  });

  final String title;
  final String subtitle;

  /// Said once the account is linked, e.g. "Study groups are unlocked."
  final String unlocked;

  final String? sectionTitle;

  /// What the feature adds: an icon, a title and a line each.
  final List<GateItem> items;

  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class GateItem {
  const GateItem(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _AccountGateState extends ConsumerState<AccountGate> {
  bool _linking = false;

  Future<void> _link() async {
    setState(() => _linking = true);
    try {
      final auth = ref.read(authServiceProvider);
      // bootstrap() hydrates the store directly, so the service has no live
      // session yet. Restoring first is what lets linkAccount() upgrade the
      // existing uid in place instead of minting a fresh anonymous profile.
      await auth.restore();
      final profile = await auth.linkAccount(
        provider: 'email',
        displayName: ref.read(userProvider).displayName,
      );
      await ref.read(userProvider.notifier).save(profile);
      if (!mounted) return;
      showAppSnack(context, 'Account linked. ${widget.unlocked}');
    } on AuthException catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.friendly);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(
          icon: Icons.lock_outline_rounded,
          title: widget.title,
          subtitle: widget.subtitle,
          action: AppActionButton(
            label: _linking ? 'Linking…' : 'Sign in or link an account',
            icon: Icons.link_rounded,
            onTap: _linking ? null : _link,
          ),
        ),
        if (widget.items.isNotEmpty)
          AppSection(
            title: widget.sectionTitle ?? 'What it adds',
            children: [
              for (var i = 0; i < widget.items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(widget.items[i].icon),
                  title: Text(widget.items[i].title),
                  subtitle: Text(widget.items[i].subtitle),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// The dialog a locked settings row opens: the same question, asked before the
/// user has navigated anywhere.
Future<bool> showAccountGateDialog(
  BuildContext context, {
  required String feature,
  required String message,
}) async {
  final link = await showAppConfirmDialog(
    context: context,
    title: '$feature needs an account',
    message: message,
    confirmLabel: 'Sign in',
    cancelLabel: 'Not now',
    icon: Icons.person_outline_rounded,
  );
  return link;
}
