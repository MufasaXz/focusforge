import '../../core/localization/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/app_mark.dart';
import '../../shared/widgets/email_auth_sheet.dart';
import '../../shared/widgets/provider_marks.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/privacy_policy_link.dart';
import 'onboarding_chrome.dart';

/// Screen 1 — the account fork.
///
/// Two ways in, one promise: the user can create an account or skip it, and
/// nothing in the flow is gated behind signing up. The screen only ever talks
/// to `authServiceProvider`; the backend behind it is an implementation
/// detail, and the providers it can actually honour — `supportedProviders` —
/// decide which rows are live and what the caption promises.
///
/// It is also routed at `/auth` on its own, so it must stand up without the
/// onboarding flow around it — hence [embedded], which suppresses the scaffold
/// the flow already provides.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.embedded = false, this.onAuthenticated});

  final bool embedded;

  /// Called after any successful path. Standalone, the screen sends the user
  /// into the rest of the onboarding flow instead.
  final VoidCallback? onAuthenticated;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  /// Which action is in flight, so only that button spins.
  String? _busy;

  /// The provider that just succeeded, so its row can hold a tick for the beat
  /// between the call returning and the screen changing.
  String? _done;

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> _run(String id, Future<UserProfile?> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = id;
      _done = null;
    });
    try {
      final profile = await action();
      if (!mounted) return;
      // Adopt the identity the auth layer just minted, immediately.
      //
      // This is load-bearing: `UserNotifier.save()` is a whole-record write,
      // so if the later onboarding steps run against the blank cold-install
      // profile they will happily overwrite the account that was just created
      // — and the user silently ends up anonymous again, locked out of study
      // groups and the leaderboard. Adopting here closes that window.
      if (profile != null) {
        ref.read(userProvider.notifier).hydrate(profile);
      }
      if (!mounted) return;
      // A held tick, not an instant cut: the user pressed a button and the
      // screen changed under them, so the beat is what connects the two.
      setState(() => _done = id);
      HapticFeedback.lightImpact();
      if (!MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(Motion.quick);
      }
      if (!mounted) return;
      _finish();
    } on AuthException catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Could not continue. Please try again."),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _finish() {
    if (_auth.needsEmailVerification) {
      context.goNamed(AppRoutes.verifyEmail);
      return;
    }
    final profile = ref.read(userProvider);
    if (profile.onboardingComplete) {
      context.goNamed(AppRoutes.dashboard);
      showAppSnack(
        context,
        tr("{0} Your setup and focus history are ready.", [
          _auth.welcomeMessage(profile),
        ]),
      );
      return;
    }
    final done = widget.onAuthenticated;
    if (_auth.isReturningUser) {
      showAppSnack(
        context,
        tr("{0} Let’s finish setting up this device.", [
          _auth.welcomeMessage(profile),
        ]),
      );
    }
    if (done != null) {
      done();
      return;
    }
    // Standalone: hand over to the flow, which skips this step when it finds
    // a session already restored.
    context.go(AppRoutes.paths[AppRoutes.onboarding]!);
  }

  /// The "Skip for now" path.
  ///
  /// Re-entering this step must not mint a second anonymous identity: the
  /// user has likely edited the profile since the first skip, and a fresh
  /// account would silently discard all of it. With a session in hand, skip
  /// simply moves on.
  Future<void> _skip() async {
    if (_busy != null) return;
    if (ref.read(userProvider).uid.isNotEmpty) {
      _finish();
      return;
    }
    await _run('skip', () => _auth.signInAnonymously());
  }

  Future<void> _email() async {
    if (_busy != null) return;
    setState(() => _busy = 'email');
    try {
      if (!mounted) return;
      final profile = await showModalBottomSheet<UserProfile>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => EmailAuthSheet(service: _auth),
      );
      if (profile == null || !mounted) return;
      ref.read(userProvider.notifier).hydrate(profile);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _finish();
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Could not open sign-in. Please try again."),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ValueListenableBuilder<AccountRecoveryStage?>(
      valueListenable: _auth.recoveryState,
      builder: (context, _, _) => _content(context),
    );
    if (widget.embedded) return content;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final providers = ref.watch(authServiceProvider).supportedProviders;
    final googleLive = providers.contains('google');
    final bottomInset = widget.embedded
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final breathingRoom = (constraints.maxHeight * 0.025).clamp(12.0, 24.0);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Gap.xl,
              breathingRoom,
              Gap.xl,
              Gap.xl + bottomInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_auth.restorationPending &&
                    _auth.recoveryState.value == null) ...[
                  Text(
                    context.tr(
                      "Your saved study data could not be loaded. Connect to the internet and try again.",
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Gap.sm),
                  FilledButton.icon(
                    onPressed: _busy == null
                        ? () => _run('restore', _auth.restore)
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.tr("Retry account recovery")),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
                Stagger(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: Gap.xxl,
                      bottom: Gap.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppMark(size: 40),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Text(
                                'FocusForge',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.xxl),
                        Text(
                          context.tr("Make room for\nwhat matters."),
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                letterSpacing: -1.2,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          context.tr(
                            "A quieter space to study, one session at a time.",
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                Stagger(
                  index: 1,
                  child: Text(
                    context.tr("Sign in to connect"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Stagger(
                  index: 2,
                  child: Text(
                    context.tr(
                      "Restore your study data, join groups and compare focus time.",
                    ),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Stagger(
                  index: 3,
                  child: ProviderRow(
                    label: context.tr("Continue with Google"),
                    leading: const GoogleMark(),
                    busy: _busy == 'google',
                    done: _done == 'google',
                    // A disabled row that still explains itself beats a row that
                    // vanishes on some builds and not others.
                    onTap: googleLive && _busy == null
                        ? () => _run(
                            'google',
                            () => _auth.linkAccount(provider: 'google'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: Gap.md),
                Stagger(
                  index: 4,
                  child: ProviderRow(
                    label: context.tr("Continue with Email"),
                    leading: const MailMark(),
                    busy: _busy == 'email',
                    onTap: _busy == null && providers.contains('email')
                        ? _email
                        : null,
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Stagger(
                  index: 5,
                  child: GhostAction(
                    label: context.tr("Skip for now"),
                    icon: Icons.arrow_forward_rounded,
                    onTap: _busy == null ? _skip : null,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Stagger(
                  index: 6,
                  child: Text(
                    googleLive
                        ? context.tr(
                            "An account is optional. You can sign in later.",
                          )
                        : providers.contains('email')
                        ? context.tr(
                            "Google sign-in is not available in this build. Use email or skip — you can link an account later.",
                          )
                        : context.tr(
                            "Account sign-in is unavailable right now. Skip to study on this device and try signing in later.",
                          ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                const PrivacyPolicyLink(),
              ],
            ),
          ),
        );
      },
    );
  }
}
