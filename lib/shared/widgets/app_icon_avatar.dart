import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_catalog.dart';
import 'icon_badge.dart';

/// The real launcher icon for an installed app, with a glyph fallback.
///
/// The icon is read from the platform and cached for the life of the process,
/// so a list of twenty rows does not make twenty channel calls on every
/// rebuild. The fallback is not decoration: on web, and for an app the user has
/// since uninstalled, there is no icon to read, and a row with an empty square
/// where its icon should be reads as broken.
class AppIconAvatar extends StatefulWidget {
  const AppIconAvatar({
    super.key,
    required this.packageId,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.size = 40,
    this.radius = 12,
  });

  final String? packageId;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double size;
  final double radius;

  @override
  State<AppIconAvatar> createState() => _AppIconAvatarState();
}

class _AppIconAvatarState extends State<AppIconAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppIconAvatar old) {
    super.didUpdateWidget(old);
    if (old.packageId != widget.packageId) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final packageId = widget.packageId;
    if (packageId == null || !AppCatalog.isSupported) return;
    final bytes = await AppCatalog.icon(packageId);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      return IconBadge(
        icon: widget.fallbackIcon,
        color: widget.fallbackColor,
        size: widget.size,
        radius: widget.radius,
      );
    }

    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Image.memory(
          bytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // A decode failure on a malformed icon falls back to the glyph
          // rather than leaving a broken-image box in the list.
          errorBuilder: (_, _, _) => IconBadge(
            icon: widget.fallbackIcon,
            color: widget.fallbackColor,
            size: widget.size,
            radius: widget.radius,
          ),
        ),
      ),
    );
  }
}
