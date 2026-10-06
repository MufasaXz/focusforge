import 'dart:async';
import 'dart:math' as math;

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
import '../../shared/widgets/icon_badge.dart';
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
      // A held tick, not an instant cut: the user pressed a button and the
      // screen changed under them, so the beat is what connects the two.
      setState(() => _done = id);
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 420));
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
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _EmailSheet(service: _auth),
    );
    if (profile == null || !mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (mounted) _finish();
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

    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg + bottomInset),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Stagger(
            index: 0,
            child: const AppMark(size: 64, semanticLabel: 'FocusForge'),
          ),
          const SizedBox(height: Gap.xl),
          Stagger(
            index: 1,
            child: Text(
              'Welcome to FocusForge',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Stagger(
            index: 2,
            child: Text(
              'Your focus starts here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const Spacer(flex: 3),
          Stagger(
            index: 3,
            child: _AuthButton(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata_rounded,
              busy: _busy == 'google',
              done: _done == 'google',
              // A disabled row that still explains itself beats a row that
              // vanishes on some builds and not others.
              onTap: googleLive
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
              label: 'Continue with Email',
              icon: Icons.mail_outline_rounded,
              busy: _busy == 'email',
              onTap: _email,
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Gap.md),
          Stagger(
            index: 7,
            child: Text(
              'By continuing you agree to our Terms & Privacy Policy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

/// One provider row. A tonal card row rather than a filled button, so the
/// options read as choices on the same surface as everything else.
///
/// It presses in and settles back on tap. The travel is small — this is
/// feedback that the tap landed, not an animation to watch — but on a screen
/// whose only job is to move the user along, an inert card makes the app feel
/// slower than it is.
class _AuthButton extends StatefulWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.busy = false,
    this.done = false,
  });

  final String label;
  final IconData icon;

  /// Null when the backend cannot mint this credential: the row stays on
  /// screen, dimmed and inert, so the option is explained rather than hidden.
  final VoidCallback? onTap;
  final bool busy;

  /// True for the beat after this row's call succeeded.
  final bool done;

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _pressed = false;

  bool get _live => widget.onTap != null && !widget.busy && !widget.done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Listener(
      // A raw pointer listener rather than a gesture recogniser: it does not
      // enter the gesture arena, so the row's own onTap still fires normally.
      onPointerDown: _live ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: _live ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel: _live ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Card.outlined(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.item),
            side: BorderSide(
              color: widget.done ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: ListTile(
            onTap: _live ? widget.onTap : null,
            // Null makes the row informational: the provider is explained
            // rather than hidden, and the disabled palette says so.
            enabled: _live,
            leading: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: IconBadge(
                key: ValueKey(widget.done),
                icon: widget.done ? Icons.check_rounded : widget.icon,
                color: cs.primary,
                size: 34,
                radius: Radii.tile,
              ),
            ),
            title: Text(widget.label, style: theme.textTheme.titleSmall),
            trailing: widget.busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
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
///
/// The sheet validates as the user types rather than on submit. The button
/// stays disabled until the form would actually succeed, so the only thing a
/// tap can produce is a result — never a lecture about a field that was
/// obviously empty. A failed call shakes the sheet, which is the one piece of
/// motion here that carries information rather than decoration.
class _EmailSheet extends StatefulWidget {
  const _EmailSheet({required this.service});

  final AuthService service;

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// Which fields the user has left. A field is only ever marked wrong once it
  /// has been visited, so the sheet does not open covered in red.
  bool _emailTouched = false;
  bool _passwordTouched = false;

  bool _signUp = false;
  bool _busy = false;
  bool _reveal = false;
  bool _succeeded = false;

  /// Drives the error shake.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _email.addListener(_onChanged);
    _password.addListener(_onChanged);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Deliberately permissive: one `@`, a dot in the domain, no spaces. Anything
  /// stricter rejects addresses that are legal, and the backend is the real
  /// authority on whether an address exists.
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String get _emailValue => _email.text.trim();
  bool get _emailValid => _emailPattern.hasMatch(_emailValue);

  /// Sign-in accepts any non-empty password — an old account may predate the
  /// current rule. Sign-up enforces the rule, because that is the only moment
  /// the password can still be chosen.
  bool get _passwordValid =>
      _signUp ? _password.text.length >= 8 : _password.text.isNotEmpty;

  bool get _canSubmit =>
      !_busy && !_succeeded && _emailValid && _passwordValid;

  String? get _emailError {
    if (!_emailTouched || _emailValue.isEmpty) return null;
    return _emailValid ? null : 'Enter a full email address';
  }

  String? get _passwordError {
    if (!_passwordTouched || _password.text.isEmpty) return null;
    if (!_passwordValid) return 'Use at least 8 characters';
    return null;
  }

  /// 0..1, for the sign-up strength bar. Length dominates — it is the only
  /// factor that reliably matters — with a bonus for mixing character classes.
  double get _strength {
    final p = _password.text;
    if (p.isEmpty) return 0;
    final length = (p.length / 16).clamp(0.0, 1.0);
    var classes = 0;
    if (RegExp(r'[a-z]').hasMatch(p)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(p)) classes++;
    if (RegExp(r'\d').hasMatch(p)) classes++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) classes++;
    return (length * 0.7 + (classes / 4) * 0.3).clamp(0.0, 1.0);
  }

  void _shakeIt() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _shake.forward(from: 0);
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      // A tap on a disabled-looking button still has to answer. Mark both
      // fields visited so the reason appears, and shake.
      setState(() {
        _emailTouched = true;
        _passwordTouched = true;
      });
      _shakeIt();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final profile = _signUp
          ? await widget.service.signUpWithEmail(_emailValue, _password.text)
          : await widget.service.signInWithEmail(_emailValue, _password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _succeeded = true;
      });
      HapticFeedback.lightImpact();
      // Hold the tick long enough to read, then hand the profile back.
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _shakeIt();
      showAppSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
    }
  }

  Future<void> _reset() async {
    final email = _emailValue;
    if (!_emailValid) {
      setState(() => _emailTouched = true);
      _shakeIt();
      return;
    }
    try {
      await widget.service.sendPasswordReset(email);
      if (!mounted) return;
      showAppSnack(
        context,
        'If an account exists for $email, a reset link is on its way.',
        icon: Icons.mark_email_read_outlined,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _shakeIt();
      showAppSnack(
        context,
        e.friendly,
        icon: Icons.error_outline_rounded,
        danger: true,
      );
    }
  }

  void _toggleMode() {
    setState(() {
      _signUp = !_signUp;
      // The rule for the password changes with the mode, so the verdict on
      // what is already typed has to be re-earned rather than carried over.
      _passwordTouched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Three decaying swings. A shake is a nudge, not a bounce — it has to
        // be over before the user has finished reading the message.
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 6) * 9 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.xl + keyboard),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _signUp ? 'Create your account' : 'Sign in with email',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_succeeded)
                    Icon(
                      Icons.check_circle_rounded,
                      color: cs.primary,
                      size: 24,
                    ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'Stored on this device for now — nothing is sent to a server.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.xl),
              AppTextField(
                controller: _email,
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofocus: true,
                errorText: _emailError,
                // Only once the field is actually right — a tick on a
                // half-typed address would be a lie.
                suffix: _emailValid
                    ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                    : null,
                onChanged: (_) {
                  if (!_emailTouched) setState(() => _emailTouched = true);
                },
              ),
              const SizedBox(height: Gap.md),
              AppTextField(
                controller: _password,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: !_reveal,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_submit()),
                errorText: _passwordError,
                helperText: _signUp && _passwordError == null
                    ? 'At least 8 characters'
                    : null,
                suffix: IconButton(
                  onPressed: () => setState(() => _reveal = !_reveal),
                  tooltip: _reveal ? 'Hide password' : 'Show password',
                  iconSize: 18,
                  color: cs.onSurfaceVariant,
                  icon: Icon(
                    _reveal
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                onChanged: (_) {
                  if (!_passwordTouched) setState(() => _passwordTouched = true);
                },
              ),
              if (_signUp && _password.text.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                _StrengthBar(value: _strength),
              ],
              const SizedBox(height: Gap.xl),
              PrimaryAction(
                label: _signUp ? 'Create account' : 'Sign in',
                busy: _busy,
                enabled: _canSubmit,
                onTap: _submit,
                icon: _succeeded ? Icons.check_rounded : null,
              ),
              const SizedBox(height: Gap.xs),
              GhostAction(
                label: _signUp
                    ? 'I already have an account'
                    : 'Create an account instead',
                onTap: _busy ? null : _toggleMode,
              ),
              GhostAction(
                label: 'Forgot password?',
                onTap: _busy ? null : () => unawaited(_reset()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sign-up password meter. It says what it measures and nothing more —
/// a "weak" verdict on a short password is a fact, not a scolding.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (value) {
      < 0.34 => ('Weak', cs.error),
      < 0.67 => ('Fair', cs.tertiary),
      _ => ('Strong', cs.primary),
    };

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        // Fixed width so the bar does not jump as the word changes length.
        SizedBox(
          width: 46,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
