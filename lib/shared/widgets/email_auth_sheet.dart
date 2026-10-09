import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/services/auth_service.dart';
import 'form_controls.dart';
import 'tonal_panel.dart';

/// Email sign-in / sign-up sheet.
///
/// Kept in one sheet with a mode toggle: two nearly identical screens would
/// drift apart, and the user's mental model is "email", not "log in" vs "sign
/// up". It is shared rather than owned by the sign-in screen because the
/// profile's link-account flow opens the same form — the two callers differ
/// only in what they do with the profile that comes back.
///
/// The sheet validates as the user types rather than on submit. The button
/// stays disabled until the form would actually succeed, so the only thing a
/// tap can produce is a result — never a lecture about a field that was
/// obviously empty. A failed call shakes the sheet, which is the one piece of
/// motion here that carries information rather than decoration.
///
/// Pops the [UserProfile] the credential produced, or null if dismissed.
class EmailAuthSheet extends StatefulWidget {
  const EmailAuthSheet({super.key, required this.service});

  final AuthService service;

  @override
  State<EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<EmailAuthSheet>
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

  bool get _canSubmit => !_busy && !_succeeded && _emailValid && _passwordValid;

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
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _shakeIt();
      showAppSnack(
        context,
        'Could not sign in. Please try again.',
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
              const Eyebrow(
                'YOUR FOCUSFORGE ACCOUNT',
                icon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: Gap.lg),
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
                widget.service.usesRemoteCredentials
                    ? 'Sign-in is handled by Firebase. Your detailed study log stays on this device.'
                    : 'Stored on this device for now — nothing is sent to a server.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
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
                  if (!_passwordTouched) {
                    setState(() => _passwordTouched = true);
                  }
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
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
