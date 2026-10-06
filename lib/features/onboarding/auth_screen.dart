import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/mesh_background.dart';
import '../../shared/widgets/stagger.dart';
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
/// and canvas the flow already provides.
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
    setState(() => _busy = id);
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
      _finish();
    } on AuthException catch (e) {
      if (!mounted) return;
      showGlassSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
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
    if (ref.read(userProvider).uid.isNotEmpty) {
      _finish();
      return;
    }
    await _run('skip', () => _auth.signInAnonymously());
  }

  Future<void> _email() async {
    // Same staleness guard as [_run]: the sheet talks to the service
    // directly, so the service has to be current before it opens.
    await _syncSession();
    if (!mounted) return;
    final profile = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _EmailSheet(service: _auth),
    );
    if (profile == null || !mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    if (mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MeshBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final t = context.glass;
    final providers = ref.watch(authServiceProvider).supportedProviders;
    final missing = [
      if (!providers.contains('google')) 'Google',
      if (!providers.contains('apple')) 'Apple',
    ];
    final bottomInset = widget.embedded
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg + bottomInset),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Stagger(
            index: 0,
            child: GlassIconBadge(
              icon: Icons.local_fire_department_rounded,
              color: t.accentPrimary,
              size: 64,
              radius: Radii.card,
              glow: 0.7,
            ),
          ),
          const SizedBox(height: Gap.xl),
          Stagger(
            index: 1,
            child: Text(
              'Welcome to FocusForge',
              textAlign: TextAlign.center,
              style: context.type.headlineMedium,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Stagger(
            index: 2,
            child: Text(
              'Your focus starts here',
              textAlign: TextAlign.center,
              style: context.type.bodyLarge?.copyWith(color: t.textTertiary),
            ),
          ),
          const Spacer(flex: 3),
          Stagger(
            index: 3,
            child: _AuthButton(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata_rounded,
              busy: _busy == 'google',
              onTap: providers.contains('google')
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
            child: _AuthButton(
              label: 'Continue with Apple',
              icon: Icons.apple,
              busy: _busy == 'apple',
              onTap: providers.contains('apple')
                  ? () => _run(
                      'apple',
                      () => _auth.linkAccount(provider: 'apple'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: Gap.md),
          Stagger(
            index: 5,
            child: _AuthButton(
              label: 'Continue with Email',
              icon: Icons.mail_outline_rounded,
              busy: _busy == 'email',
              onTap: _email,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Stagger(
            index: 6,
            child: GhostAction(
              label: 'Skip for now',
              icon: Icons.arrow_forward_rounded,
              onTap: _skip,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Stagger(
            index: 7,
            child: Text(
              missing.isEmpty
                  ? 'Google and Apple are not connected yet — for now those '
                        'buttons create a local account on this device. You '
                        'can link a real account later without losing '
                        'anything.'
                  : '${missing.join(' and ')} sign-in is not available in '
                        'this build. Use email or skip — you can link a real '
                        'account later without losing anything.',
              textAlign: TextAlign.center,
              style: context.type.bodySmall?.copyWith(color: t.textTertiary),
            ),
          ),
          const SizedBox(height: Gap.md),
          Stagger(
            index: 8,
            child: Text(
              'By continuing you agree to our Terms & Privacy Policy.',
              textAlign: TextAlign.center,
              style: context.type.labelSmall?.copyWith(color: t.textTertiary),
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

/// One provider row. A glass panel rather than a filled Material button, so
/// the three options read as choices on the same surface as everything else.
class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;

  /// Null when the backend cannot mint this credential: the row stays on
  /// screen, dimmed and inert, so the option is explained rather than hidden.
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        onTap: busy ? null : onTap,
        child: GlassPanel(
          level: 2,
          radius: Radii.item,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              GlassIconBadge(
                icon: icon,
                color: t.accentPrimary,
                size: 34,
                radius: Radii.tile,
              ),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(label, style: context.type.titleSmall)),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accentPrimary,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: t.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Email sign-in / sign-up sheet.
///
/// Kept in one sheet with a mode toggle: two nearly identical screens would
/// drift apart, and the user's mental model is "email", not "log in" vs "sign
/// up".
class _EmailSheet extends StatefulWidget {
  const _EmailSheet({required this.service});

  final AuthService service;

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final profile = _signUp
          ? await widget.service.signUpWithEmail(email, _password.text)
          : await widget.service.signInWithEmail(email, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on AuthException catch (e) {
      if (!mounted) return;
      showGlassSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showGlassSnack(
        context,
        'Enter your email first, then tap reset.',
        icon: Icons.error_outline_rounded,
        danger: true,
      );
      return;
    }
    try {
      await widget.service.sendPasswordReset(email);
      if (!mounted) return;
      showGlassSnack(
        context,
        'If an account exists for $email, a reset link is on its way.',
        icon: Icons.mark_email_read_outlined,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      showGlassSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.md + keyboard),
      child: GlassPanel(
        level: 2,
        radius: Radii.hero,
        blur: t.blurL2,
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.track,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),
              Text(
                _signUp ? 'Create your account' : 'Sign in with email',
                style: context.type.titleLarge,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'Stored on this device for now — nothing is sent to a server.',
                style: context.type.bodySmall?.copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: Gap.xl),
              GlassTextField(
                controller: _email,
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofocus: true,
              ),
              const SizedBox(height: Gap.md),
              GlassTextField(
                controller: _password,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Gap.xl),
              PrimaryAction(
                label: _signUp ? 'Create account' : 'Sign in',
                busy: _busy,
                onTap: _submit,
              ),
              const SizedBox(height: Gap.xs),
              GhostAction(
                label: _signUp
                    ? 'I already have an account'
                    : 'Create an account instead',
                onTap: () => setState(() => _signUp = !_signUp),
              ),
              GhostAction(label: 'Forgot password?', onTap: _reset),
            ],
          ),
        ),
      ),
    );
  }
}
