import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_strings.dart';
import '../../core/providers/app_update_providers.dart';
import '../../core/services/app_update_service.dart';

/// Lives inside the signed-in/guest shell, never the sign-up/permissions flow.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _busy = false;
  GoRouterDelegate? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context)?.routerDelegate;
    if (router != _router) {
      _router?.removeListener(_scheduleCheck);
      _router = router;
      _router?.addListener(_scheduleCheck);
    }
    // Depend on route visibility so a dismissed dialog can release a prompt.
    if (ModalRoute.isCurrentOf(context) != false) _scheduleCheck();
  }

  @override
  void dispose() {
    _router?.removeListener(_scheduleCheck);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  bool get _canPrompt {
    if (!mounted || !ref.read(appUpdatePromptAllowedProvider)) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    if (ModalRoute.isCurrentOf(context) == false ||
        Navigator.of(context, rootNavigator: true).canPop()) {
      return false;
    }
    final path = _router?.state.uri.path;
    return path == null ||
        const ['/dashboard', '/shield', '/focus', '/profile'].contains(path);
  }

  void _scheduleCheck() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) => unawaited(_check()));
    binding.ensureVisualUpdate();
  }

  Future<void> _check() async {
    if (_busy || !_canPrompt) return;
    _busy = true;
    try {
      final service = ref.read(appUpdateServiceProvider);
      final release = await service.check();
      if (!mounted) return;
      if (release == null || !_canPrompt || service.wasShown(release)) return;
      final dialog = showAppUpdateDialog(context, release);
      // Mark this exact version/build once shown. Later/back/outside-tap all
      // dismiss it; manual checks remain available in About.
      try {
        await service.markShown(release);
      } catch (_) {
        // Preference failures must not crash navigation or trap the dialog.
      }
      await dialog;
    } catch (_) {
      // A background update check must never interrupt startup.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appUpdatePromptAllowedProvider, (previous, next) {
      if (next && previous != true) _scheduleCheck();
    });
    return widget.child;
  }
}

Future<void> showAppUpdateDialog(BuildContext context, AppRelease release) =>
    showDialog<void>(
      context: context,
      builder: (_) => _UpdateDialog(release: release),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});
  final AppRelease release;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await launchUrl(
        widget.release.page,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (opened) {
        Navigator.of(context).pop();
        return;
      }
    } catch (_) {
      // Keep the dialog dismissible and avoid surfacing platform exceptions.
    }
    if (mounted) {
      setState(() {
        _opening = false;
        _error = 'Could not open GitHub. Try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    icon: const Icon(Icons.system_update_alt_rounded),
    title: Text(context.tr('A new FocusForge is ready')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Version ${widget.release.version} · Build ${widget.release.buildNumber}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Text(
          context.tr(
            'See what’s new and download the update from our GitHub release page. You can keep studying and update later.',
          ),
        ),
        if (widget.release.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            widget.release.notes,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            context.tr(_error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.tr('Later')),
      ),
      FilledButton(
        onPressed: _opening ? null : _open,
        child: Text(context.tr('View update')),
      ),
    ],
  );
}

class CheckForUpdatesTile extends ConsumerStatefulWidget {
  const CheckForUpdatesTile({super.key});
  @override
  ConsumerState<CheckForUpdatesTile> createState() =>
      _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends ConsumerState<CheckForUpdatesTile> {
  bool _checking = false;
  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final service = ref.read(appUpdateServiceProvider);
      final release = await service.check(force: true);
      if (!mounted) return;
      if (release != null) {
        await showAppUpdateDialog(context, release);
        await service.markShown(release);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'No newer compatible release found. If you’re offline, try again when connected.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Could not check for updates. Try again later.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.system_update_alt_rounded),
    title: Text(
      context.tr(_checking ? 'Checking for updates…' : 'Check for updates'),
    ),
    subtitle: Text(context.tr('GitHub releases · optional updates')),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _checking ? null : _check,
  );
}
