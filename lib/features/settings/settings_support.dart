import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/icon_badge.dart';

/// Shared chrome for the settings sub-screens.
///
/// The seven settings screens all need the same three things — a centred
/// frosted dialog, a full-width action button and a snackbar that matches the
/// surface it floats over. Keeping them here means the modal on the privacy
/// screen and the modal on strict mode are the same modal, rather than two
/// that drifted apart. It deliberately lives beside the screens instead of in
/// `shared/widgets`, because nothing outside this folder uses it.

/// Opens a centred frosted dialog and returns its result.
///
/// [showDialog] gives its child the full screen with tight constraints, so the
/// centring, the width cap and the keyboard inset handling all have to be done
/// here — a bare surface would stretch edge to edge. The backdrop blur is one
/// of the few the design allows: a modal floats over the page, and the blur is
/// what says so.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final insets = MediaQuery.viewInsetsOf(context);
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Gap.xl,
            Gap.xl,
            Gap.xl,
            Gap.xl + insets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.hero),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(Radii.hero),
                  ),
                  padding: const EdgeInsets.all(Gap.xl),
                  child: builder(context),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A yes/no dialog, optionally gated on typing [requirePhrase] exactly.
///
/// The typed gate is the point of the destructive actions in this folder: a
/// tap is too easy to give away, and spelling the commitment out is the
/// cheapest way to make the user mean it.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  String? requirePhrase,
  String? fieldHint,
  String? footnote,
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    // A decision that erases data should not be dismissible by a stray tap.
    barrierDismissible: requirePhrase == null && !destructive,
    builder: (context) => _ConfirmBody(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      requirePhrase: requirePhrase,
      fieldHint: fieldHint,
      footnote: footnote,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result ?? false;
}

/// A single-field prompt. Returns the trimmed value, or null if cancelled.
Future<String?> showAppInputDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String actionLabel,
  String? hintText,
  IconData icon = Icons.edit_rounded,
  TextInputType? keyboardType,
  String? footnote,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => _InputBody(
      title: title,
      message: message,
      actionLabel: actionLabel,
      hintText: hintText,
      icon: icon,
      keyboardType: keyboardType,
      footnote: footnote,
    ),
  );
}

/// Full-width primary action for a settings page.
///
/// Destructive verbs pass [destructive] rather than a raw colour so that
/// "delete" and "clear" cannot end up two slightly different reds. A caller
/// that passes [accent] gets the secondary, outlined treatment instead.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = accent;

    if (a != null) {
      return OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: a,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return FilledButton.icon(
      onPressed: onTap,
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              minimumSize: const Size.fromHeight(48),
            )
          : FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Height of the docked navigation bar (`navigationBarTheme` in [AppTheme])
/// plus the gap that keeps a floating snackbar clear of it.
const double _snackBarNavClearance = 80 + Gap.sm;

/// Themed snackbar. Floating, and lifted clear of the nav bar — these screens
/// live inside the tab shell, where a default snackbar would sit behind it.
void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          Gap.lg,
          Gap.lg,
          Gap.lg,
          _snackBarNavClearance + MediaQuery.paddingOf(context).bottom,
        ),
      ),
    );
}

class _ConfirmBody extends StatefulWidget {
  const _ConfirmBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.icon,
    this.requirePhrase,
    this.fieldHint,
    this.footnote,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData icon;
  final String? requirePhrase;
  final String? fieldHint;
  final String? footnote;

  @override
  State<_ConfirmBody> createState() => _ConfirmBodyState();
}

class _ConfirmBodyState extends State<_ConfirmBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      widget.requirePhrase == null ||
      _controller.text.trim() == widget.requirePhrase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = widget.destructive ? cs.error : cs.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(icon: widget.icon, color: accent, size: 40, radius: 12),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(widget.message, style: Theme.of(context).textTheme.bodyMedium),
        if (widget.requirePhrase != null) ...[
          const SizedBox(height: Gap.lg),
          Text(
            'Type “${widget.requirePhrase}” to continue.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.sm),
          _DialogField(
            controller: _controller,
            hintText: widget.fieldHint,
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (widget.footnote != null) ...[
          const SizedBox(height: Gap.md),
          Text(
            widget.footnote!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Gap.xl),
        Row(
          children: [
            Expanded(
              child: _DialogButton(
                label: widget.cancelLabel,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _DialogButton(
                label: widget.confirmLabel,
                destructive: widget.destructive,
                filled: true,
                onTap: _canConfirm
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InputBody extends StatefulWidget {
  const _InputBody({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.icon,
    this.hintText,
    this.keyboardType,
    this.footnote,
  });

  final String title;
  final String message;
  final String actionLabel;
  final IconData icon;
  final String? hintText;
  final TextInputType? keyboardType;
  final String? footnote;

  @override
  State<_InputBody> createState() => _InputBodyState();
}

class _InputBodyState extends State<_InputBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = _controller.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(icon: widget.icon, color: cs.primary, size: 40, radius: 12),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(widget.message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Gap.lg),
        _DialogField(
          controller: _controller,
          hintText: widget.hintText,
          keyboardType: widget.keyboardType,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        if (widget.footnote != null) ...[
          const SizedBox(height: Gap.md),
          Text(
            widget.footnote!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Gap.xl),
        Row(
          children: [
            Expanded(
              child: _DialogButton(
                label: 'Cancel',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _DialogButton(
                label: widget.actionLabel,
                filled: true,
                onTap: value.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.tile),
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onSubmitted: (_) => onChanged?.call(controller.text),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
        cursorColor: cs.primary,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

    if (!filled) {
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          minimumSize: const Size.fromHeight(48),
        ),
        child: text,
      );
    }

    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: destructive ? cs.error : cs.primary,
        foregroundColor: destructive ? cs.onError : cs.onPrimary,
        minimumSize: const Size.fromHeight(48),
      ),
      child: text,
    );
  }
}
