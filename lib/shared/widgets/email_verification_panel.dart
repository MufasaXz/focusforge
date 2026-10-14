import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/services/auth_service.dart';
import 'privacy_policy_link.dart';
import 'form_controls.dart';

/// A pending Firebase credential is not an unlocked app account.
class EmailVerificationPanel extends StatefulWidget {
  const EmailVerificationPanel({
    super.key,
    required this.service,
    required this.onVerified,
    required this.onSignedOut,
  });
  final AuthService service;
  final ValueChanged<UserProfile> onVerified;
  final VoidCallback onSignedOut;
  @override
  State<EmailVerificationPanel> createState() => _EmailVerificationPanelState();
}

class _EmailVerificationPanelState extends State<EmailVerificationPanel>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _message;
  bool _error = false;
  Timer? _cooldown;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldown?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(_refresh(silent: true));
    }
  }

  int get _secondsLeft {
    final next = widget.service.verificationResendAvailableAt;
    if (next == null) return 0;
    return (next.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
      0,
      60,
    );
  }

  void _startCooldown() {
    _cooldown?.cancel();
    if (_secondsLeft == 0) return;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsLeft == 0) timer.cancel();
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final profile = await widget.service.refreshEmailVerification();
      if (!mounted) return;
      if (profile != null) {
        widget.onVerified(profile);
      } else if (!silent) {
        setState(() {
          _message = 'Your email is not verified yet. Open the link in your inbox, check spam, then try again.';
          _error = true;
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.friendly;
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not check verification. Connect to the internet and try again.';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _secondsLeft > 0) return;
    setState(() => _busy = true);
    try {
      await widget.service.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _message = 'Verification email sent. Check your inbox and spam folder.';
        _error = false;
      });
      _startCooldown();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.friendly;
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not send the email. Please try again.';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.signOut();
      if (mounted) widget.onSignedOut();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.friendly;
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not sign out. Please try again.';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = widget.service.verificationEmail ?? 'your email address';
    final seconds = _secondsLeft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_unread_outlined, size: 44, color: cs.primary),
        const SizedBox(height: Gap.lg),
        Text(
          'Verify your email',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.md),
        Text(
          email,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Open the verification link in your inbox, then return to FocusForge. Need a link? Send a verification email below. Your account stays locked until you verify it.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Wrong address? Use a different account below. Your setup on this device is kept.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (_message != null) ...[
          const SizedBox(height: Gap.md),
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _error ? cs.error : cs.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: Gap.xl),
        PrimaryAction(
          label: 'I’ve verified my email',
          busy: _busy,
          onTap: _busy ? null : () => _refresh(),
        ),
        const SizedBox(height: Gap.sm),
        GhostAction(
          label: seconds > 0
              ? 'Resend in ${seconds}s'
              : 'Send verification email',
          onTap: _busy || seconds > 0 ? null : _send,
        ),
        GhostAction(
          label: 'Use a different account',
          onTap: _busy ? null : _signOut,
        ),
        const PrivacyPolicyLink(),
      ],
    );
  }
}
