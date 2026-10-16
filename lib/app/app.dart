import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import 'router.dart';
import '../core/localization/app_strings.dart';
import 'theme/app_theme.dart';
import '../shared/widgets/account_recovery_overlay.dart';

/// The application root.
///
/// All this does is bind the router to the two generated themes and keep the
/// system chrome in step with whichever one is active — see the shell, which
/// is where the status-bar brightness is actually driven from.
class FocusForgeApp extends ConsumerWidget {
  const FocusForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(themeSettingsProvider);

    return MaterialApp.router(
      title: 'FocusForge',
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: AppStrings.localizationsDelegates,
      localeListResolutionCallback: (locales, _) =>
          AppStrings.resolve(locales ?? const []),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(palette: settings.palette),
      darkTheme: AppTheme.dark(
        palette: settings.palette,
        amoled: settings.amoled,
      ),
      themeMode: settings.mode.mode,
      routerConfig: router,
      builder: (context, child) => AccountRecoveryOverlay(
        service: ref.read(authServiceProvider),
        child: child ?? const SizedBox.shrink(),
      ),
      scrollBehavior: const _NoGlowScrollBehavior(),
    );
  }
}

/// Material's default stretch overscroll indicator is drawn with a tinted
/// glow that reads as a smudge over a flat tonal surface. The app suppresses
/// it and relies on the platform's own edge feedback instead.
class _NoGlowScrollBehavior extends MaterialScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
