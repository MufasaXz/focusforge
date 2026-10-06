import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import 'router.dart';
import 'theme/glass_theme.dart';

/// The application root.
///
/// All this does is bind the router to the two glass themes and keep the
/// system chrome in step with whichever one is active — see [SystemChrome] in
/// the shell, which is where the status-bar brightness is actually driven from.
class FocusForgeApp extends ConsumerWidget {
  const FocusForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'FocusForge',
      debugShowCheckedModeBanner: false,
      theme: GlassTheme.light(),
      darkTheme: GlassTheme.dark(),
      themeMode: mode,
      routerConfig: router,
      scrollBehavior: const _NoGlowScrollBehavior(),
    );
  }
}

/// Touch platforms get a stretch overscroll indicator that fights the glass
/// surfaces; the app draws its own edge treatment instead.
class _NoGlowScrollBehavior extends MaterialScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
