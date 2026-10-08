import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/bootstrap.dart';
import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_store.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import 'settings_support.dart';

/// Data & Privacy — the screen that has to tell the truth about storage.
///
/// Distinguishes detailed local records from optional shared summaries. On the web there is no
/// file system to write an export to, so exporting copies to the clipboard
/// instead — and says so, rather than pretending a download happened.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(userProvider);

    return AppPage(
      title: 'Data & Privacy',
      subtitle: 'Local-first by default',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: 'Your data',
            children: [
              ListTile(
                leading: IconBadge(
                  icon: Icons.smartphone_outlined,
                  color: cs.tertiary,
                  size: 42,
                  radius: 12,
                ),
                title: const Text('Your detailed history stays here'),
                subtitle: const Text(
                  'Focus sessions, shield events, badges and settings '
                  'are stored locally. Optional social and parent features '
                  'share only the summaries described below.',
                ),
              ),
            ],
          ),
          AppSection(
            title: 'What’s in the cloud',
            footnote: user.isAnonymous
                ? 'Group sharing needs a linked account. Parent sharing starts '
                      'only when you pair this device.'
                : 'Sharing starts when you join a group, opt into the board, '
                      'or pair with a parent.',
            children: const [
              ListTile(
                title: Text('Your profile'),
                subtitle: Text('Display name and avatar'),
                leading: Icon(Icons.person_outline),
              ),
              ListTile(
                title: Text('Study group membership'),
                subtitle: Text(
                  'Membership, name, weekly minutes and active focus status · Members only',
                ),
                leading: Icon(Icons.groups_outlined),
              ),
              ListTile(
                title: Text('Leaderboard scores'),
                subtitle: Text('Weekly focus hours only'),
                leading: Icon(Icons.leaderboard_outlined),
              ),
              ListTile(
                title: Text('Parent control'),
                subtitle: Text(
                  'Paired study summaries, installed app names and rules set by your parent',
                ),
                leading: Icon(Icons.shield_outlined),
              ),
            ],
          ),
          AppSection(
            title: 'Actions',
            children: [
              ListTile(
                title: const Text('Export all data (JSON)'),
                subtitle: Text(
                  kIsWeb
                      ? 'Copies every stored key to the clipboard'
                      : 'Preview and copy every stored key',
                ),
                leading: const Icon(Icons.ios_share),
                trailing: const AppChevron(),
                onTap: () => _export(context, ref),
              ),
              ListTile(
                title: const Text('Clear local analytics'),
                subtitle: const Text(
                  'Removes focus history, totals and subject progress',
                ),
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: cs.error,
                ),
                trailing: const AppChevron(),
                onTap: () => _clearAnalytics(context, ref),
              ),
              ListTile(
                title: const Text('Delete account'),
                subtitle: const Text('Erases every local record'),
                leading: Icon(Icons.delete_outline, color: cs.error),
                trailing: const AppChevron(),
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
          AppSection(
            title: 'Legal',
            children: [
              ListTile(
                title: const Text('Privacy policy'),
                leading: const Icon(Icons.privacy_tip_outlined),
                trailing: const AppChevron(),
                onTap: () => _showInfo(
                  context,
                  title: 'Privacy policy',
                  body:
                      'Detailed sessions, screen time and screen checks stay on your device. '
                      'Groups share your name, weekly focus minutes and current focus timer with members. '
                      'The public weekly board shares your name and total only when you opt in. '
                      'A paired parent receives study summaries and installed app names to choose rules. '
                      'Firebase stores these optional records. No ad network or analytics SDK is used. '
                      'Leaving a group removes your membership and progress row. You can export local '
                      'data or delete your account here.',
                ),
              ),
              ListTile(
                title: const Text('Terms of service'),
                leading: const Icon(Icons.gavel_outlined),
                trailing: const AppChevron(),
                onTap: () => _showInfo(
                  context,
                  title: 'Terms of service',
                  body:
                      'FocusForge is provided as-is, without warranty. Strict '
                      'Mode is a commitment device you choose to enable — it '
                      'does not replace emergency services, and the always '
                      'allowed list is there so that it never can. You own '
                      'your data; the app claims no licence over it.',
                ),
              ),
              ListTile(
                title: const Text('Open source licences'),
                subtitle: const Text('Flutter, Riverpod and bundled assets'),
                leading: const Icon(Icons.article_outlined),
                trailing: const AppChevron(),
                onTap: () => _showLicences(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- Export ---------------------------------------------------------------

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final data = ref.read(localStoreProvider).exportAll();
    final json = const JsonEncoder.withIndent('  ').convert(data);

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: json));
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Copied ${data.length} stored keys to the clipboard as JSON.',
      );
      return;
    }

    if (!context.mounted) return;
    final copied = await showAppDialog<bool>(
      context: context,
      builder: (context) => _ExportBody(json: json, keyCount: data.length),
    );
    if (copied == true && context.mounted) {
      showAppSnack(context, 'JSON copied to the clipboard.');
    }
  }

  // -- Clear analytics ------------------------------------------------------

  Future<void> _clearAnalytics(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Clear local analytics?',
      message:
          'This removes your focus history, streak totals, subject '
          'progress and shield statistics from this device. Badges and '
          'weekly targets are kept.',
      confirmLabel: 'Clear analytics',
      icon: Icons.cleaning_services_rounded,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final store = ref.read(localStoreProvider);
    await store.setMap(StoreKeys.stats, const GamificationStats().toJson());
    await store.setList(StoreKeys.sessions, const []);
    await store.setList(StoreKeys.breathEvents, const []);

    // Subject counters are derived from the session log, but the stored rows
    // keep the last derived value, so zero the progress here too — in memory
    // and on disk — while `weekTarget` is left alone: targets are the user's
    // settings, not analytics.
    final subjects = [
      for (final s in ref.read(subjectsProvider))
        s.copyWith(minutesToday: 0, weekDone: 0).toJson(),
    ];
    await store.setList(StoreKeys.subjects, subjects);

    // `hydrate` is the only public write path these notifiers expose outside
    // their own provider file, and feeding them the same empty state is what
    // keeps memory and storage from disagreeing until the next launch.
    ref.read(statsProvider.notifier).hydrate(const GamificationStats());
    ref.read(sessionsProvider.notifier).hydrate(const []);
    ref.read(breathEventsProvider.notifier).hydrate(const []);
    ref.read(subjectsProvider.notifier).hydrate(subjects);

    if (!context.mounted) return;
    showAppSnack(context, 'Local analytics cleared.');
  }

  // -- Delete account -------------------------------------------------------

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete your account?',
      message:
          'Every local record is erased: profile, sessions, shields and '
          'badges. Group memberships and their progress rows are removed '
          'before the account is deleted. Unlink parent control and opt out '
          'of the public board first to remove those older records. This cannot be undone.',
      requirePhrase: 'DELETE',
      fieldHint: 'Type DELETE',
      confirmLabel: 'Delete everything',
      icon: Icons.delete_forever_rounded,
      destructive: true,
      footnote: 'You will be returned to onboarding with a blank slate.',
    );
    if (!confirmed || !context.mounted) return;

    // Read while the context is certainly live: the credential call below
    // crosses an async gap before the reset needs the container.
    final container = ProviderScope.containerOf(context, listen: false);

    // The auth service removes group membership while it can still authorise
    // cloud writes. Local records are kept if cleanup or credential deletion
    // fails so the user can retry.
    try {
      await ref.read(authServiceProvider).deleteAccount();
    } on AuthException catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, e.friendly);
      return;
    }

    // Clearing the store is not enough: the live notifiers still hold every
    // record that was just "deleted", and would write it straight back on
    // their next save. `resetPersistedState` blanks them all in the one place
    // that knows how to hydrate them, and re-arms the demo-history marker so
    // the onboarding that follows starts from a genuinely empty slate.
    await resetPersistedState(container);

    if (!context.mounted) return;
    context.go(AppRoutes.paths[AppRoutes.onboarding]!);
  }

  // -- Legal ----------------------------------------------------------------

  void _showLicences(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'FocusForge',
      applicationVersion: '1.0.1',
      applicationLegalese: 'MIT licensed · built with Flutter',
    );
  }

  void _showInfo(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showAppDialog<void>(
      context: context,
      builder: (context) => _InfoBody(title: title, body: body),
    );
  }
}

class _ExportBody extends StatelessWidget {
  const _ExportBody({required this.json, required this.keyCount});

  final String json;
  final int keyCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: Icons.description_rounded,
              color: cs.primary,
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'Exported JSON',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          '$keyCount stored keys. Nothing has left this device.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.lg),
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.item),
            color: cs.surfaceContainerHigh,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.md),
            child: SelectableText(
              json,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                label: 'Close',
                icon: Icons.close_rounded,
                accent: cs.onSurfaceVariant,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: AppActionButton(
                label: 'Copy JSON',
                icon: Icons.copy_rounded,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoBody extends StatelessWidget {
  const _InfoBody({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: Icons.article_rounded,
              color: cs.primary,
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Text(body, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Gap.xl),
        AppActionButton(
          label: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
