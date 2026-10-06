import '../../app/theme/app_theme.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/bootstrap.dart';
import '../../app/router.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_store.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
import 'settings_support.dart';

/// Data & Privacy — the screen that has to tell the truth about storage.
///
/// The distinction it draws is between what is *local* (everything the app
/// records) and what a linked account *would* sync. On the web there is no
/// file system to write an export to, so exporting copies to the clipboard
/// instead — and says so, rather than pretending a download happened.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(userProvider);

    return GlassPage(
      title: 'Data & Privacy',
      subtitle: 'Local-first by default',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Your data', icon: Icons.lock_rounded),
          GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassIconBadge(
                  icon: Icons.smartphone_rounded,
                  color: cs.tertiary,
                  size: 42,
                  radius: 12,
                  glow: 0.25,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Everything stays on this device',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Focus sessions, shield events, badges and settings '
                        'are stored locally. Usage patterns are never uploaded '
                        'to any server.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          GlassSection(
            title: 'What’s in the cloud',
            footnote: user.isAnonymous
                ? 'You are signed in anonymously, so nothing is synced yet. '
                      'Linking an account is what turns these on.'
                : 'Synced with your linked account.',
            children: const [
              GlassRow(
                title: 'Your profile',
                subtitle: 'Display name and avatar',
                icon: Icons.person_rounded,
              ),
              GlassRow(
                title: 'Study group membership',
                subtitle: 'Which groups you belong to',
                icon: Icons.groups_rounded,
              ),
              GlassRow(
                title: 'Leaderboard scores',
                subtitle: 'Weekly focus hours only',
                icon: Icons.leaderboard_rounded,
              ),
              GlassRow(
                title: 'Shield preferences',
                subtitle: 'So your blocks follow you between devices',
                icon: Icons.shield_rounded,
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Actions',
            children: [
              GlassRow(
                title: 'Export all data (JSON)',
                subtitle: kIsWeb
                    ? 'Copies every stored key to the clipboard'
                    : 'Preview and copy every stored key',
                icon: Icons.ios_share_rounded,
                trailing: const GlassChevron(),
                onTap: () => _export(context, ref),
              ),
              GlassRow(
                title: 'Clear local analytics',
                subtitle: 'Removes focus history, totals and subject progress',
                icon: Icons.cleaning_services_rounded,
                iconColor: cs.error,
                trailing: const GlassChevron(),
                onTap: () => _clearAnalytics(context, ref),
              ),
              GlassRow(
                title: 'Delete account',
                subtitle: 'Erases every local record',
                icon: Icons.delete_outline_rounded,
                iconColor: cs.error,
                trailing: const GlassChevron(),
                showDivider: false,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
          GlassSection(
            title: 'Legal',
            children: [
              GlassRow(
                title: 'Privacy policy',
                icon: Icons.privacy_tip_rounded,
                trailing: const GlassChevron(),
                onTap: () => _showInfo(
                  context,
                  title: 'Privacy policy',
                  body:
                      'FocusForge keeps your usage data on this device. There '
                      'is no analytics SDK and no ad network, and no server '
                      'receives your focus history. The only data that leaves '
                      'the device is what you explicitly sync by linking an '
                      'account: your profile, group membership, leaderboard '
                      'scores and shield preferences. You can export or delete '
                      'everything from this screen at any time.',
                ),
              ),
              GlassRow(
                title: 'Terms of service',
                icon: Icons.gavel_rounded,
                trailing: const GlassChevron(),
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
              GlassRow(
                title: 'Open source licences',
                subtitle: 'Flutter, Riverpod and bundled assets',
                icon: Icons.article_rounded,
                trailing: const GlassChevron(),
                showDivider: false,
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
      showGlassSnack(
        context,
        'Copied ${data.length} stored keys to the clipboard as JSON.',
      );
      return;
    }

    if (!context.mounted) return;
    final copied = await showGlassDialog<bool>(
      context: context,
      builder: (context) => _ExportBody(json: json, keyCount: data.length),
    );
    if (copied == true && context.mounted) {
      showGlassSnack(context, 'JSON copied to the clipboard.');
    }
  }

  // -- Clear analytics ------------------------------------------------------

  Future<void> _clearAnalytics(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassConfirmDialog(
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
    showGlassSnack(context, 'Local analytics cleared.');
  }

  // -- Delete account -------------------------------------------------------

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Delete your account?',
      message:
          'Every local record is erased: profile, sessions, shields and '
          'badges. This cannot be undone.',
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

    // The credential goes first and can refuse — offline, or when Firebase
    // wants a fresh sign-in. Report that and keep every local record: wiping
    // them under a credential that still exists is the half-deletion this
    // ordering exists to prevent.
    try {
      await ref.read(authServiceProvider).deleteAccount();
    } on AuthException catch (e) {
      if (!context.mounted) return;
      showGlassSnack(context, e.friendly);
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
      applicationVersion: '0.1.0',
      applicationLegalese: 'MIT licensed · built with Flutter',
    );
  }

  void _showInfo(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showGlassDialog<void>(
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
            GlassIconBadge(
              icon: Icons.description_rounded,
              color: cs.primary,
              size: 40,
              radius: 12,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text('Exported JSON', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          '$keyCount stored keys. Nothing has left this device.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.lg),
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.item),
            color: cs.surfaceContainer.withValues(alpha: 0.45),
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
              child: GlassActionButton(
                label: 'Close',
                icon: Icons.close_rounded,
                accent: cs.onSurfaceVariant,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: GlassActionButton(
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
            GlassIconBadge(
              icon: Icons.article_rounded,
              color: cs.primary,
              size: 40,
              radius: 12,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Text(body, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Gap.xl),
        GlassActionButton(
          label: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
