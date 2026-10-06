import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/stagger.dart';

/// Furniture shared by every onboarding step.
///
/// The flow is the app's first impression, so the steps must not each invent
/// their own button, field or snackbar — one set of primitives is what keeps
/// seven screens looking like one product. Everything here is stock Material 3
/// built from the scheme's own roles, so the flow sits on the same tonal
/// surfaces as the rest of the app.

/// The standard step layout: scrollable body, pinned primary action, optional
/// secondary action and footnote.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.primaryLabel = 'Continue',
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.secondary,
    this.footnote,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Widget? secondary;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.xl),
            children: [
              Stagger(
                index: 0,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (subtitle != null)
                Stagger(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: t.onSurfaceVariant),
                    ),
                  ),
                ),
              const SizedBox(height: Gap.xl),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            Gap.xl,
            Gap.sm,
            Gap.xl,
            Gap.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            children: [
              PrimaryAction(
                label: primaryLabel,
                onTap: onPrimary,
                enabled: primaryEnabled,
                busy: primaryBusy,
              ),
              if (secondary != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: secondary,
                ),
              if (footnote != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    footnote!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: t.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The flow's primary call to action — a full-width [FilledButton].
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active = enabled && !busy;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        // Disabled and busy both read as a non-interactive button, so the
        // spinner never competes with a live tap target.
        onPressed: active ? onTap : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (icon != null) ...[
                    const SizedBox(width: Gap.sm),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Quiet secondary action — "Skip for now", "I already have an account".
class GhostAction extends StatelessWidget {
  const GhostAction({super.key, required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          minimumSize: const Size.fromHeight(48),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (icon != null) ...[
              const SizedBox(width: Gap.xs),
              Icon(icon, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// The flow's text field, a filled Material [TextField].
///
/// The tonal fill marks the input area and the primary-coloured focus border
/// is the M3 focus tell; the field carries no elevation of its own.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.errorText,
    this.helperText,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Set only when the field is wrong, never while it is merely empty — an
  /// error on an untouched field tells the user off for nothing.
  final String? errorText;

  /// A hint that is always true, such as what a password has to contain.
  final String? helperText;

  /// Trailing affordance inside the field — the password visibility toggle.
  final Widget? suffix;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = BorderRadius.circular(Radii.item);
    final wrong = errorText != null;

    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autofocus: autofocus,
      style: theme.textTheme.bodyLarge,
      cursorColor: cs.primary,
      cursorRadius: const Radius.circular(Radii.pill),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        prefixIcon: icon == null
            ? null
            : Icon(
                icon,
                size: 20,
                color: wrong ? cs.error : cs.onSurfaceVariant,
              ),
        suffixIcon: suffix,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.lg,
        ),
        errorText: errorText,
        helperText: helperText,
        helperStyle: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        errorStyle: theme.textTheme.bodySmall?.copyWith(color: cs.error),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: wrong ? cs.error : cs.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
      ),
    );
  }
}

/// Floating snackbar. Errors from the auth service surface here with [danger]
/// set so a failure never looks like a success.
void showAppSnack(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline_rounded,
  bool danger = false,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: danger ? cs.error : cs.primary),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        // A tonal surface, not the inverse one: it keeps the error and primary
        // accents legible in both brightnesses and matches the cards below.
        backgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(Gap.lg),
        duration: const Duration(seconds: 4),
      ),
    );
}
