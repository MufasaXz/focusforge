import '../../core/localization/app_strings.dart';

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
import '../../core/app_version.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_store.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/glass_surface.dart';
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
        title: context.tr("Account & privacy"),
        subtitle: context.tr("Your account. Your choices."),
        onBack: _busy ? () {} : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The account, at a glance: who is signed in and what that means,
            // stated on its own surface rather than inside the list it leads.
            _AccountHeader(user: user, busy: _busy, ref: ref),
            const SizedBox(height: Gap.xl),
            AppSection(
              title: context.tr("Sign-in"),
              children: [
                _Row(
                  icon: user.isAnonymous
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  title: user.isAnonymous
                      ? context.tr("Sign in or create an account")
                      : context.tr("Sign out"),
                  subtitle: context.tr(
                    "Your setup and local focus history are kept",
                  ),
                  onTap: _busy
                      ? null
                      : () => user.isAnonymous
                            ? context.goNamed(AppRoutes.auth)
                            : _signOut(context, ref),
                ),
              ],
            ),
            AppSection(
              title: context.tr("Account actions"),
              footnote: context.tr(
                "Guest study and Shield events stay on this device. Linked accounts privately back up sessions, subjects, plans and goals. Clear local analytics before handing your phone to someone else.",
              ),
              children: [
                _Row(
                  icon: Icons.ios_share,
                  title: context.tr("Export all data (JSON)"),
                  subtitle: kIsWeb
                      ? context.tr("Copies every stored key to the clipboard")
                      : context.tr("Preview and copy every stored key"),
                  onTap: _busy ? null : () => _export(context, ref),
                ),
                // Withdrawing is one tap, as granting was. Off clears the
                // in-memory list at once; the next Shield visit asks again.
                SwitchListTile(
                  secondary: Icon(
                    Icons.apps_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  title: Text(
                    context.tr("App list access"),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    context.tr(
                      "Lets Shield and Home read installed apps and today’s usage on this device. Never uploaded.",
                    ),
                  ),
                  value: ref.watch(appListConsentProvider),
                  onChanged: _busy
                      ? null
                      : (on) => on
                            ? confirmAppListAccess(context, ref)
                            : ref
                                  .read(appListConsentProvider.notifier)
                                  .set(false),
                ),
                _Row(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: cs.error,
                  title: context.tr("Clear local analytics"),
                  subtitle: context.tr(
                    "Removes focus history, totals and subject progress",
                  ),
                  onTap: _busy ? null : () => _clearAnalytics(context, ref),
                ),
                ListTile(
                  leading: Icon(Icons.person_remove_outlined, color: cs.error),
                  title: Text(
                    context.tr("Delete account"),
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    ref.read(authServiceProvider).usesRemoteCredentials &&
                            !user.isAnonymous
                        ? context.tr(
                            "Permanently remove your account and progress",
                          )
                        : context.tr("Permanently erase your profile and data"),
                  ),
                  trailing: const AppChevron(),
                  onTap: _busy ? null : () => _deleteAccount(context, ref),
                ),
              ],
            ),
            AppSection(
              title: context.tr("What’s in the cloud"),
              footnote: context.tr(
                "Backups are private to your account. Public sharing starts only when you opt in.",
              ),
              children: [
                _CloudItem(
                  icon: Icons.person_outline,
                  title: context.tr("Your account"),
                  detail: context.tr(
                    "Credentials are handled by Firebase. Profile, subjects, plans, goals and sessions are backed up privately.",
                  ),
                ),
                _CloudItem(
                  icon: Icons.workspace_premium_outlined,
                  title: context.tr("Earned achievements"),
                  detail: context.tr(
                    "Badge IDs and dates are backed up privately for linked accounts.",
                  ),
                ),
                _CloudItem(
                  icon: Icons.photo_outlined,
                  title: context.tr("Profile avatar"),
                  detail: context.tr(
                    "Backed up with your account; shared only when leaderboard sharing is on.",
                  ),
                ),
                _CloudItem(
                  icon: Icons.groups_outlined,
                  title: context.tr("Study groups"),
                  detail: context.tr(
                    "Name, weekly minutes and focus status · members only",
                  ),
                ),
                _CloudItem(
                  icon: Icons.leaderboard_outlined,
                  title: context.tr("Leaderboard"),
                  detail: context.tr(
                    "Name, level and weekly minutes · shared when you opt in",
                  ),
                ),
              ],
            ),
            AppSection(
              title: context.tr("Legal"),
              children: [
                _Row(
                  icon: Icons.privacy_tip_outlined,
                  title: context.tr("Privacy policy"),
                  onTap: _busy
                      ? null
                      : () => openPrivacyResource(context, privacyPolicyUrl),
                ),
                _Row(
                  icon: Icons.gavel_outlined,
                  title: context.tr("Terms of service"),
                  onTap: _busy
                      ? null
                      : () => _showInfo(
                          context,
                          title: context.tr("Terms of service"),
                          body: context.tr(
                            "FocusForge is provided as-is, without warranty. Strict Mode is a commitment device you choose to enable — it does not replace emergency services, and the always allowed list is there so that it never can. You own your data; the app claims no licence over it.",
                          ),
                        ),
                ),
                _Row(
                  icon: Icons.article_outlined,
                  title: context.tr("Open source licences"),
                  onTap: _busy ? null : () => _showLicences(context),
                ),
              ],
            ),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => openPrivacyResource(context, accountDeletionUrl),
                child: Text(context.tr("Request deletion on the web")),
              ),
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
        context.tr("Copied {0} stored keys to the clipboard as JSON.", [
          data.length,
        ]),
      );
      return;
    }

    if (!context.mounted) return;
    final copied = await showAppDialog<bool>(
      context: context,
      builder: (context) => _ExportBody(json: json, keyCount: data.length),
    );
    if (copied == true && context.mounted) {
      showAppSnack(context, context.tr("JSON copied to the clipboard."));
    }
  }

  // -- Clear analytics ------------------------------------------------------

  Future<void> _clearAnalytics(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: context.tr("Clear local analytics?"),
      message: context.tr(
        "This removes your focus history, streak totals, subject progress and shield statistics from this device. Badges and weekly targets are kept. Saved cloud study history can return when you recover your account.",
      ),
      confirmLabel: context.tr("Clear analytics"),
      icon: Icons.cleaning_services_rounded,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final store = ref.read(localStoreProvider);
    await ref.read(timerProvider.notifier).discardPendingHistory();
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
    showAppSnack(context, context.tr("Local analytics cleared."));
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
              Text(
                context.tr("Keep the app open until this finishes."),
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
      retrying
          ? context.tr("Re-verifying your account…")
          : context.tr("Verifying your account…"),
    );
    await auth.reauthenticate(password: password);
    return true;
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: context.tr("Delete your account?"),
      message: context.tr(
        "This action is irreversible and will delete your profile, achievements, and all progress.",
      ),
      footnote: context.tr(
        "Shared scores and group membership are removed too. A linked account requires a fresh sign-in check. Keep the app open until deletion finishes.",
      ),
      confirmLabel: context.tr("Delete account"),
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
              context.tr(
                "Deletion paused. Some cloud records may already be removed. Your account and local history are kept; retry to finish.",
              ),
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
        _showDeletionProgress(context, context.tr("Deleting your account…"));
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
                    ? context.tr(
                        "Deletion paused. Some cloud records may already be removed. Your account and local history are kept; retry to finish.",
                      )
                    : context.tr(
                        "Verification cancelled. Your account has not been deleted.",
                      )
              : error.friendly,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(
          context,
          context.tr(
            "Deletion could not finish. Your local history is kept. Please retry or use the account-deletion page for help.",
          ),
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
      title: context.tr("Sign out?"),
      message: context.tr(
        "Your study data stays on this device. Online changes are privately backed up to your account; pending changes sync when you sign in again. Your shared leaderboard row stays visible.",
      ),
      confirmLabel: context.tr("Sign out"),
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
          context.tr("Signed out. Your focus history is safe on this device."),
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(
          context,
          context.tr("Could not sign out. Please try again."),
        );
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
      applicationVersion: kAppVersion,
      applicationLegalese: context.tr("MIT licensed · built with Flutter"),
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
        Text(
          context.tr("Verify it’s you"),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Gap.md),
        Text(
          widget.retrying
              ? context.tr(
                  "Verification expired. Enter your password again to finish deletion; some cloud records may already be removed.",
                )
              : context.tr(
                  "Enter your account password to confirm deletion. Nothing is removed until verification succeeds.",
                ),
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
          decoration: InputDecoration(labelText: context.tr("Password")),
        ),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Gap.sm),
            child: Text(
              context.tr("Verify and delete"),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr("Cancel")),
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
                context.tr("Exported JSON"),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          context.tr("{0} stored keys. Nothing has left this device.", [
            keyCount,
          ]),
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
                label: context.tr("Close"),
                icon: Icons.close_rounded,
                accent: cs.onSurfaceVariant,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: AppActionButton(
                label: context.tr("Copy JSON"),
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
          label: context.tr("Close"),
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The account, summarised on its own card at the top of the page.
///
/// One glance answers the two questions the rest of the page hangs off: who is
/// signed in, and where the data lives. Putting it on a surface of its own
/// keeps the list below it for *actions* rather than for status.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.user,
    required this.busy,
    required this.ref,
  });

  final UserProfile user;
  final bool busy;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final linked = !user.isAnonymous;

    return ContentCard(
      color: Color.alphaBlend(
        cs.primary.withValues(alpha: linked ? 0.08 : 0.04),
        cs.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: (linked ? cs.primary : cs.onSurfaceVariant).withValues(
                  alpha: 0.14,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                linked
                    ? Icons.verified_user_outlined
                    : Icons.smartphone_rounded,
                color: linked ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName.isEmpty
                        ? context.tr("Your FocusForge account")
                        : user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    linked
                        ? context.tr("Linked · backed up privately")
                        : context.tr("On this device only"),
                    style: tt.labelMedium?.copyWith(
                      color: linked ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A navigable row: icon, label, optional one-line note and a chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? cs.onSurfaceVariant),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const AppChevron(),
      onTap: onTap,
    );
  }
}

/// A non-tappable fact about what syncs: icon, a short name and a short gloss.
class _CloudItem extends StatelessWidget {
  const _CloudItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: IconBadge(icon: icon, color: cs.tertiary, size: 38, radius: 11),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        detail,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
