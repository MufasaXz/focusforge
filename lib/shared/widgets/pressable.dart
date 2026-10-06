import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// Scale-on-press wrapper. Springs back with a slight overshoot so taps feel
/// physical rather than binary.
///
/// Built on [FocusableActionDetector] rather than a bare [GestureDetector]: the
/// app ships to web, where a control that cannot be reached with Tab or fired
/// with Enter is simply broken. Hover and focus are shown as a wash over the
/// child instead of a rectangular ring, because the same wrapper carries pills,
/// cards and bare icons — a ring drawn from the widget's bounds would be wrong
/// on most of them, while a wash follows whatever shape the child already has.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;
  bool _focused = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null || widget.onLongPress != null;

    Color? wash;
    if (enabled && _focused) {
      wash = cs.primary.withValues(alpha: 0.16);
    } else if (enabled && _hover) {
      wash = Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.05);
    }

    final scale = _down
        ? widget.scale
        : _focused
        ? 1.02
        : _hover
        ? 1.012
        : 1.0;

    // `srcATop` keeps the child's shape and alpha and takes only the colour
    // from the shader, so the wash never spills past a rounded edge.
    final washColor = wash;
    final child = washColor == null
        ? widget.child
        : ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) =>
                LinearGradient(colors: [washColor, washColor])
                    .createShader(rect),
            child: widget.child,
          );

    return Semantics(
      button: true,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (value) {
          if (_hover == value) return;
          setState(() => _hover = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused == value) return;
          setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedScale(
            scale: scale,
            // Fast in, springy out — the asymmetry is what makes it feel like a
            // physical control rather than a CSS transition.
            duration: Duration(milliseconds: _down ? 90 : 340),
            curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Rounded gradient badge used for app icons and section glyphs.
///
/// Takes either a Material [icon] or a short text [glyph] — never an emoji, so
/// that every badge in the app shares one weight, corner radius and lighting.
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({
    super.key,
    this.icon,
    this.glyph,
    required this.color,
    this.size = 40,
    this.radius = 12,
    this.glow = 0,
    this.semanticLabel,
  });

  final IconData? icon;
  final String? glyph;
  final Color color;
  final double size;
  final double radius;

  /// 0..1 — adds an outer accent bloom.
  final double glow;

  /// Decorative by default: the badge normally sits beside a label that already
  /// names it, and hearing "M" announced for a maths tile is noise. Pass a
  /// label only when the badge is the thing that carries the meaning.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final badge = _buildBadge(context);
    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(label: semanticLabel, image: true, child: badge);
  }

  Widget _buildBadge(BuildContext context) {

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.38),
            color.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.48)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18 + 0.30 * glow),
            blurRadius: 12 + 14 * glow,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top-left inner highlight, matching the panel treatment.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.06).withValues(alpha: 0)],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: glyph != null
                ? Text(
                    glyph!,
                    style: TextStyle(
                      fontSize: size * 0.34,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: -0.2,
                    ),
                  )
                : Icon(icon, size: size * 0.50, color: color),
          ),
        ],
      ),
    );
  }
}
