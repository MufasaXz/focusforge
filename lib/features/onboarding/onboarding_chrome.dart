import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/stagger.dart';

/// Furniture shared by every onboarding step.
///
/// The flow is the app's first impression, so the steps must not each invent
/// their own button, field or snackbar — one set of primitives is what keeps
/// seven screens looking like one product. Everything here is built from the
/// glass system rather than Material defaults, because a stock `ElevatedButton`
/// or a white `TextField` would read as a different app.

/// Text colour that stays legible on the accent gradient. The dark theme's
/// accents are pastels (dark text) and the light theme's are saturated (white
/// text), so this cannot be a constant.
Color onAccentColor(GlassTokens t) =>
    ThemeData.estimateBrightnessForColor(t.accentPrimary) == Brightness.dark
    ? Colors.white
    : const Color(0xFF0C1226);

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
    final t = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.xl),
            children: [
              Stagger(
                index: 0,
                child: Text(title, style: context.type.headlineMedium),
              ),
              if (subtitle != null)
                Stagger(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Text(
                      subtitle!,
                      style: context.type.bodyMedium?.copyWith(
                        color: t.textSecondary,
                      ),
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
                    style: context.type.bodySmall?.copyWith(
                      color: t.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The flow's primary call to action — a full-width accent-gradient capsule.
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
    final t = context.glass;
    final on = onAccentColor(t);
    final active = enabled && !busy;

    return Pressable(
      onTap: active ? onTap : null,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: GlassPanel(
          radius: Radii.pill,
          accent: t.accentPrimary,
          glowStrength: active ? 0.9 : 0,
          padding: const EdgeInsets.symmetric(vertical: Gap.lg),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [t.accentPrimary, t.accentSecondary],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: on),
                )
              else ...[
                Text(
                  label,
                  style: context.type.labelLarge?.copyWith(
                    color: on,
                    fontSize: 15,
                    letterSpacing: 0.1,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: Gap.sm),
                  Icon(icon, size: 18, color: on),
                ],
              ],
            ],
          ),
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
    final t = context.glass;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: context.type.labelLarge?.copyWith(color: t.textTertiary),
            ),
            if (icon != null) ...[
              const SizedBox(width: Gap.xs),
              Icon(icon, size: 16, color: t.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Glass text field. Deliberately not a Material [TextField] with a themed
/// decoration: the panel supplies the surface, so the input has no border, no
/// fill and no elevation of its own.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return GlassPanel(
      level: 2,
      radius: Radii.item,
      sheen: false,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: t.textTertiary),
              const SizedBox(width: Gap.md),
            ],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                autofocus: autofocus,
                style: context.type.bodyLarge,
                cursorColor: t.accentPrimary,
                cursorRadius: const Radius.circular(Radii.pill),
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: context.type.bodyLarge?.copyWith(
                    color: t.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating glass snackbar. Errors from the auth service surface here with
/// [danger] set so a failure never looks like a success.
void showGlassSnack(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline_rounded,
  bool danger = false,
}) {
  final t = context.glass;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: GlassPanel(
          level: 2,
          radius: Radii.item,
          sheen: false,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: danger ? t.danger : t.accentPrimary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  message,
                  style: context.type.bodyMedium?.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(Gap.lg),
        duration: const Duration(seconds: 4),
      ),
    );
}
