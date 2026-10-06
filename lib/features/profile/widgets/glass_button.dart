import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../shared/widgets/glass_surface.dart';

/// Full-width primary action for the profile sheets.
///
/// The design system has no button of its own — every other surface is a row
/// or a pill — but a sheet needs one unambiguous commit action. The label ink
/// is picked from the active brightness rather than fixed: the accent is a
/// light blue on dark and a deep blue on light, so a single ink colour would
/// fail contrast in one of the two themes.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.accent,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? accent;

  /// Swaps the label for a spinner and blocks taps while a write is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final a = accent ?? t.accentPrimary;
    final enabled = onTap != null && !busy;
    final ink = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0A1020)
        : Colors.white;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // The visible label already says it; without this the row is announced
      // twice.
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled ? onTap : null,
        scale: 0.97,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.item),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [a, Color.lerp(a, t.accentSecondary, 0.45)!],
              ),
              border: Border.all(color: a.withValues(alpha: 0.85)),
              boxShadow: [
                BoxShadow(
                  color: a.withValues(alpha: 0.30),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: ink,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: ink),
                        const SizedBox(width: Gap.sm),
                      ],
                      Text(
                        label,
                        style: context.type.labelLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
