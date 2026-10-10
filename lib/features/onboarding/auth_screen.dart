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
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/email_auth_sheet.dart';
import '../../shared/widgets/provider_marks.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/tonal_panel.dart';
import 'focus_preview.dart';
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

  /// Re-anchors the auth layer on the profile the app actually holds.
  ///
  /// `AuthService` now takes the stored profile as the base for every
  /// credential operation, so this is no longer what keeps the user's edits
  /// from being lost; it only keeps the service's in-memory cache — and the
  /// `signedIn` flag the flow reads — in step with `UserNotifier`, which the
  /// auth layer never hears from directly.
  ///
  /// Skipped while no session exists: a cold install has a blank profile, and
  /// the auth layer must mint a uid rather than adopt an empty one.
  Future<void> _syncSession() async {
    final current = ref.read(userProvider);
    if (current.uid.isEmpty) return;
    await _auth.updateProfile(current);
  }

  Future<void> _run(String id, Future<UserProfile?> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = id;
      _done = null;
    });
    try {
      await _syncSession();
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
        await ref.read(userProvider.notifier).save(profile);
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
          'Could not continue. Please try again.',
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _finish() {
    final done = widget.onAuthenticated;
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
      await _syncSession();
      if (!mounted) return;
      final profile = await showModalBottomSheet<UserProfile>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => EmailAuthSheet(service: _auth),
      );
      if (profile == null || !mounted) return;
      await ref.read(userProvider.notifier).save(profile);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _finish();
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not open sign-in. Please try again.',
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
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
                Stagger(
                  index: 0,
                  child: GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const AppMark(size: 32),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Text(
                                  'FocusForge',
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                            ],
                          ),
                          const FocusPreview(),
                          const Eyebrow('LESS NOISE. MORE YOU.'),
                          const SizedBox(height: Gap.md),
                          Text(
                            'Make room for\nwhat matters.',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(letterSpacing: -1.2),
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            'Build a study rhythm. Protect your attention. See your progress.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                Stagger(
                  index: 1,
                  child: Text(
                    'Your space starts here',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Stagger(
                  index: 2,
                  child: Text(
                    'Sign in for study groups, the leaderboard and parent linking.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Stagger(
                  index: 3,
                  child: ProviderRow(
                    label: 'Continue with Google',
                    subtitle: 'A familiar way to sign in',
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
                    label: 'Continue with Email',
                    subtitle: 'Your email. Your study space.',
                    leading: const MailMark(),
                    busy: _busy == 'email',
                    onTap: _busy == null ? _email : null,
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Stagger(
                  index: 5,
                  child: GhostAction(
                    label: 'Skip for now',
                    icon: Icons.arrow_forward_rounded,
                    onTap: _busy == null ? _skip : null,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Stagger(
                  index: 6,
                  child: Text(
                    googleLive
                        ? 'No account is required. Skipping keeps everything on '
                              'this device.'
                        : 'Google sign-in is not available in this build. Use email '
                              'or skip — you can link a real account later without '
                              'losing anything.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Stagger(
                  index: 7,
                  child: Text(
                    'Your study log stays on this device.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
