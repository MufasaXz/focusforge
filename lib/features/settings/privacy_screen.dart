import 'dart:async';
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
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_store.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/privacy_policy_link.dart';
import 'settings_support.dart';

/// Data & Privacy — the screen that has to tell the truth about storage.
///
/// Distinguishes detailed local records from optional shared summaries. On the web there is no
/// file system to write an export to, so exporting copies to the clipboard
/// instead — and says so, rather than pretending a download happened.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;
  final _deletionStatus = ValueNotifier('Verifying your account…');
  DialogRoute<void>? _progressRoute;
  NavigatorState? _progressNavigator;

  @override
  void dispose() {
    _deletionStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(userProvider);

    return PopScope(
      canPop: !_busy,
      child: AppPage(
        title: 'Account & privacy',
        subtitle: 'Your account. Your choices.',
        onBack: _busy ? () {} : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSection(
              title: 'Account',
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(
                    user.displayName.isEmpty
                        ? 'Your FocusForge account'
                        : user.displayName,
                  ),
                  subtitle: Text(
                    user.isAnonymous ? 'On this device · no account required' : 'Linked account · detailed history stays on this device',
                  ),
                ),
                ListTile(
                  leading: Icon(
                    user.isAnonymous
                        ? Icons.login_rounded
                        : Icons.logout_rounded,
                  ),
                  title: Text(
                    user.isAnonymous
                        ? 'Sign in or create an account'
                        : 'Sign out',
                  ),
                  subtitle: const Text(
                    'Your setup and local focus history are kept',
                  ),
                  trailing: const AppChevron(),
                  onTap: _busy
                      ? null
                      : () => user.isAnonymous
                            ? context.goNamed(AppRoutes.auth)
                            : _signOut(context, ref),
                ),
                ListTile(
                  leading: Icon(Icons.person_remove_outlined, color: cs.error),
                  title: Text(
                    'Delete account',
                    style: TextStyle(color: cs.error),
                  ),
                  subtitle: Text(
                    ref.read(authServiceProvider).usesRemoteCredentials &&
                            !user.isAnonymous
                        ? 'Permanently remove your account, achievements and progress'
                        : 'Permanently erase your profile and data from this device',
                  ),
                  trailing: const AppChevron(),
                  onTap: _busy ? null : () => _deleteAccount(context, ref),
                ),
              ],
            ),
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
                    'Focus sessions, shield events and settings '
                    'are stored locally and kept when you sign out. They belong '
                    'to this device, so signing in again restores its setup. '
                    'Optional sharing uses this device’s totals. Clear local '
                    'analytics before handing your phone to someone else.',
                  ),
                ),
              ],
            ),
            AppSection(
              title: 'What’s in the cloud',
              footnote: 'Sharing starts when you join a group or opt into the board. Badge backups are private.',
              children: const [
                ListTile(
                  title: Text('Your account'),
                  subtitle: Text(
                    'Sign-in credentials are handled by Firebase. Profile choices and avatar stay on this device.',
                  ),
                  leading: Icon(Icons.person_outline),
                ),
                ListTile(
                  title: Text('Earned achievements'),
                  subtitle: Text(
                    'Badge IDs and earned dates are backed up privately for linked accounts. '
                    'Sign in to the same account to recover them. Detailed sessions stay on this device.',
                  ),
                  leading: Icon(Icons.workspace_premium_outlined),
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
                  subtitle: Text(
                    'Display name, account ID, level and weekly focus minutes · Visible to signed-in users when you opt in',
                  ),
                  leading: Icon(Icons.leaderboard_outlined),
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
                  onTap: _busy ? null : () => _export(context, ref),
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
                  onTap: _busy ? null : () => _clearAnalytics(context, ref),
                ),
              ],
            ),
            AppSection(
              title: 'Legal',
              children: [
                ListTile(
                  title: const Text('Privacy policy'),
                  subtitle: const Text('Read the full policy on our website'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  trailing: const AppChevron(),
                  onTap: _busy
                      ? null
                      : () => openPrivacyResource(context, privacyPolicyUrl),
                ),
                ListTile(
                  title: const Text('Request deletion on the web'),
                  subtitle: const Text(
                    'For account help or remaining cloud records',
                  ),
                  leading: const Icon(Icons.person_remove_outlined),
                  trailing: const AppChevron(),
                  onTap: _busy
                      ? null
                      : () => openPrivacyResource(context, accountDeletionUrl),
                ),
                ListTile(
                  title: const Text('Terms of service'),
                  leading: const Icon(Icons.gavel_outlined),
                  trailing: const AppChevron(),
                  onTap: _busy
                      ? null
                      : () => _showInfo(
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
                  onTap: _busy ? null : () => _showLicences(context),
                ),
              ],
            ),
          ],
        ),
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

  // -- Account session -------------------------------------------------------

  void _showDeletionProgress(BuildContext context, String status) {
    _deletionStatus.value = status;
    if (_progressRoute != null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: Gap.lg),
              ValueListenableBuilder<String>(
                valueListenable: _deletionStatus,
                builder: (context, message, child) => Semantics(
                  liveRegion: true,
                  child: Text(message, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: Gap.md),
              const Text(
                'Keep the app open until this finishes.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    _progressRoute = route;
    _progressNavigator = navigator;
    unawaited(navigator.push(route));
  }

  void _dismissDeletionProgress() {
    final route = _progressRoute;
    _progressRoute = null;
    if (route != null && route.isActive) {
      _progressNavigator?.removeRoute(route);
    }
    _progressNavigator = null;
  }

  Future<bool> _verifyDeletionOwner(
    BuildContext context,
    AuthService auth,
    UserProfile profile, {
    bool retrying = false,
  }) async {
    if (!auth.usesRemoteCredentials || profile.isAnonymous) return true;
    String? password;
    if (auth.supportsPasswordReauthentication) {
      _dismissDeletionProgress();
      password = await showAppDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeleteAccountPasswordBody(retrying: retrying),
      );
      if (password == null || !context.mounted) return false;
    }
    // Google accounts reopen their provider sign-in through this same seam.
    // The password is used only for this credential check; it is never stored.
    if (!context.mounted) return false;
    _showDeletionProgress(
      context,
      retrying ? 'Re-verifying your account…' : 'Verifying your account…',
    );
    await auth.reauthenticate(password: password);
    return true;
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete your account?',
      message: 'This action is irreversible and will delete your profile, achievements, and all progress.',
      footnote: 'Shared scores and group membership are removed too. A linked account requires a fresh sign-in check. Keep the app open until deletion finishes.',
      confirmLabel: 'Delete account',
      icon: Icons.person_remove_outlined,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final auth = ref.read(authServiceProvider);
    final profile = ref.read(userProvider);
    var suspended = false;
    var deleted = false;
    setState(() => _busy = true);
    try {
      // Even a currently signed-in linked account confirms ownership before
      // any cloud record is removed. Firebase can still expire that check
      // during a long cleanup, so allow one fresh verification and retry.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!context.mounted ||
            !await _verifyDeletionOwner(
              context,
              auth,
              profile,
              retrying: attempt > 0,
            )) {
          if (attempt > 0 && context.mounted) {
            showAppSnack(
              context,
              'Deletion paused. Some cloud records may already be removed. Your account and local history are kept; retry to finish.',
            );
          }
          return;
        }
        if (!context.mounted) return;
        container.read(accountMutationProvider.notifier).state = true;
        if (!suspended) {
          suspended = true;
          await container
              .read(achievementsProvider.notifier)
              .suspendForDeletion();
        }
        if (!context.mounted) return;
        _showDeletionProgress(context, 'Deleting your account…');
        try {
          await auth.deleteAccount();
          deleted = true;
          break;
        } on AuthException catch (error) {
          if (error.failure != AuthFailure.requiresRecentLogin || attempt > 0) {
            rethrow;
          }
        }
      }
      await resetPersistedState(container);
      _dismissDeletionProgress();
      if (context.mounted) context.goNamed(AppRoutes.onboarding);
    } on AuthException catch (error) {
      if (context.mounted) {
        showAppSnack(
          context,
          error.failure == AuthFailure.cancelled
              ? suspended
                    ? 'Deletion paused. Some cloud records may already be removed. Your account and local history are kept; retry to finish.'
                    : 'Verification cancelled. Your account has not been deleted.'
              : error.friendly,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(
          context,
          'Deletion could not finish. Your local history is kept. Please retry or use the account-deletion page for help.',
        );
      }
    } finally {
      _dismissDeletionProgress();
      container.read(accountMutationProvider.notifier).state = false;
      if (suspended && !deleted) {
        container
            .read(achievementsProvider.notifier)
            .resumeAfterFailedDeletion();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Sign out?',
      message: 'Your setup and detailed history stay on this device. Sign in again to reconnect sharing.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !context.mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(achievementsProvider.notifier).flushLocal();
      await ref.read(achievementSyncProvider)();
      await ref.read(authServiceProvider).signOut();
      // The local profile remains the base for a later sign-in, but cloud
      // features should stop presenting it as a connected credential.
      await ref
          .read(userProvider.notifier)
          .save(ref.read(userProvider).copyWith(isAnonymous: true));
      if (context.mounted) {
        context.goNamed(AppRoutes.auth);
        showAppSnack(
          context,
          'Signed out. Your focus history is safe on this device.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, 'Could not sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- Legal ----------------------------------------------------------------

  void _showLicences(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'FocusForge',
      applicationVersion: '1.0.0',
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

class _DeleteAccountPasswordBody extends StatefulWidget {
  const _DeleteAccountPasswordBody({this.retrying = false});

  final bool retrying;

  @override
  State<_DeleteAccountPasswordBody> createState() =>
      _DeleteAccountPasswordBodyState();
}

class _DeleteAccountPasswordBodyState
    extends State<_DeleteAccountPasswordBody> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isNotEmpty) {
      Navigator.of(context).pop(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Verify it’s you', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Gap.md),
        Text(
          widget.retrying
              ? 'Verification expired. Enter your password again to finish deletion; some cloud records may already be removed.'
              : 'Enter your account password to confirm deletion. Nothing is removed until verification succeeds.',
        ),
        const SizedBox(height: Gap.lg),
        TextField(
          controller: _password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: Gap.sm),
            child: Text('Verify and delete', textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
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
