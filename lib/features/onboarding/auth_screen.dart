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
import '../../shared/widgets/email_auth_sheet.dart';
import '../../shared/widgets/provider_marks.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/privacy_policy_link.dart';
import '../assistant/mascot/mascot.dart';
import '../assistant/mascot/mascot_painter.dart';
import '../assistant/mascot/mascot_rig.dart';
import 'fill_wordmark.dart';
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
  const AuthScreen({
    super.key,
    this.embedded = false,
    this.onAuthenticated,
    this.onLinked,
  });

  final bool embedded;
  final ValueChanged<UserProfile>? onLinked;

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

  /// Pip stands in the welcome and waves — nothing else, and only twice, so
  /// the page settles.
  final _pip = MascotRig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pip.wave(seconds: 2.4);
    });
  }

  @override
  void dispose() {
    _pip.dispose();
    super.dispose();
  }

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
    if (widget.onLinked != null) {
      widget.onLinked!(profile);
      return;
    }
    if (profile.onboardingComplete) {
      // Saved setup belongs to the account; permissions belong to this phone.
      ref.read(askPermissionsAfterSignInProvider.notifier).state = false;
      context.goNamed(AppRoutes.permissions);
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
    if (_auth.signedIn && _auth.current?.isAnonymous == true) {
      _finish();
      return;
    }
    await _run('skip', () => _auth.signInAnonymously());
  }

  Future<void> _email() async {
    if (_busy != null) return;
    setState(() => _busy = 'email-form');
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
            child: Column(
              children: [
                OnboardingFlowHeader(
                  index: 1,
                  total: 7,
                  title: context.tr('Account'),
                  onBack: widget.onLinked == null
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final providers = ref.watch(authServiceProvider).supportedProviders;
    final googleLive = providers.contains('google');
    final emailLive = providers.contains('email');
    final bottomInset = widget.embedded
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    final note = googleLive
        ? context.tr("An account is optional. You can sign in later.")
        : emailLive
        ? context.tr(
            "Google sign-in is not available in this build. Use email or skip — you can link an account later.",
          )
        : context.tr(
            "Account sign-in is unavailable right now. Skip to study on this device and try signing in later.",
          );

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // Intrinsic height lets the spacer below push the legal links to the
          // foot of a tall screen while still scrolling on a short one.
          child: IntrinsicHeight(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.lg,
                Gap.xl,
                Gap.lg + bottomInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_auth.restorationPending &&
                      _auth.recoveryState.value == null)
                    _RecoveryNotice(
                      onRetry: _busy == null
                          ? () => _run('restore', _auth.restore)
                          : null,
                    ),
                  // The welcome sits in the middle of the screen: Pip, the
                  // words, then the choices right under them.
                  const Spacer(),
                  const SizedBox(height: Gap.lg),
                  Stagger(
                    index: 0,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: GestureDetector(
                        onTap: () => _pip.wave(seconds: 2.4),
                        child: ExcludeSemantics(
                          child: Mascot(rig: _pip, width: 76),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Stagger(
                    index: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WelcomeHeadline(
                          text: context.tr("Welcome to FocusForge"),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                          fill: MascotColors.of(theme).body,
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          context.tr(
                            "Sign in to back up your progress and use it on any phone.",
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.xxl),
                  Stagger(
                    index: 2,
                    child: _SignInButton(
                      label: context.tr("Continue with Google"),
                      leading: const GoogleMark(size: 20),
                      primary: true,
                      busy: _busy == 'google',
                      done: _done == 'google',
                      // A disabled button that stays in place explains itself;
                      // one that vanishes on some builds does not.
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
                    index: 3,
                    child: _SignInButton(
                      label: context.tr("Continue with Email"),
                      leading: Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                      busy: _busy == 'email',
                      onTap: _busy == null && emailLive ? _email : null,
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Stagger(index: 4, child: _OrDivider(label: context.tr("or"))),
                  const SizedBox(height: Gap.sm),
                  Stagger(
                    index: 5,
                    child: Center(
                      child: TextButton(
                        onPressed: _busy == null
                            ? (widget.onLinked == null
                                  ? _skip
                                  : () => Navigator.of(context).pop())
                            : null,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: cs.onSurface,
                          textStyle: theme.textTheme.titleSmall,
                        ),
                        child: _busy == 'skip'
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                context.tr(
                                  widget.onLinked == null
                                      ? "Continue without an account"
                                      : "Keep using guest mode",
                                ),
                              ),
                      ),
                    ),
                  ),
                  // Only when a sign-in route is missing does the page need
                  // to explain itself; the usual "optional" note is gone.
                  if (!googleLive)
                    Text(
                      note,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(height: Gap.lg),
                  const _LegalLinks(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown above everything when a saved profile could not be fetched.
class _RecoveryNotice extends StatelessWidget {
  const _RecoveryNotice({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              "Your saved profile could not be loaded. Connect to the internet and try again.",
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.sm),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr("Retry account recovery")),
          ),
        ],
      ),
    );
  }
}

/// A full-width sign-in button: provider mark on the left, label centred,
/// progress or a tick on the right while it works.
class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.leading,
    required this.onTap,
    this.busy = false,
    this.done = false,
    this.primary = false,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  final bool busy;
  final bool done;

  /// The recommended way in: a solid high-contrast button rather than an
  /// outline, so the first choice reads as the first choice.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onTap != null || busy || done;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: Motion.quick,
        opacity: enabled ? 1 : .45,
        child: Material(
          color: primary ? cs.inverseSurface : cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.pill),
            side: primary
                ? BorderSide.none
                : BorderSide(color: cs.outline.withValues(alpha: .55)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 24,
                      child: Center(child: leading),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: primary ? cs.onInverseSurface : cs.onSurface,
                        ),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 24,
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : done
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = Expanded(child: Divider(color: cs.outlineVariant, height: 1));
    return ExcludeSemantics(
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// "Welcome to FocusForge", with the product name filled in letter by
/// letter. The rest of the (translated) sentence is ordinary text; a language
/// that does not keep the name verbatim gets the plain sentence.
class _WelcomeHeadline extends StatelessWidget {
  const _WelcomeHeadline({
    required this.text,
    required this.style,
    required this.fill,
  });

  static const _name = 'FocusForge';

  final String text;
  final TextStyle? style;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final at = text.indexOf(_name);
    final base = style ?? DefaultTextStyle.of(context).style;
    return Semantics(
      header: true,
      label: text,
      excludeSemantics: true,
      child: at < 0
          ? Text(text, style: base)
          : Text.rich(
              TextSpan(
                style: base,
                children: [
                  if (at > 0) TextSpan(text: text.substring(0, at)),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    // One word cannot wrap, so on a narrow phone with very
                    // large text it shrinks to the line instead of overflowing.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: FillWordmark(
                        text: _name,
                        style: base,
                        color: fill,
                      ),
                    ),
                  ),
                  if (at + _name.length < text.length)
                    TextSpan(text: text.substring(at + _name.length)),
                ],
              ),
            ),
    );
  }
}

/// Privacy policy and terms, side by side at the foot of the screen.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  static const _termsUrl = 'https://www.focus-forge.in/terms';

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      minimumSize: const Size(48, 44),
      textStyle: Theme.of(context).textTheme.labelMedium,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Gap.sm,
      children: [
        TextButton(
          style: style,
          onPressed: () => openPrivacyResource(context, privacyPolicyUrl),
          child: Text(context.tr("Privacy policy")),
        ),
        TextButton(
          style: style,
          onPressed: () => openPrivacyResource(context, _termsUrl),
          child: Text(context.tr("Terms of service")),
        ),
      ],
    );
  }
}
