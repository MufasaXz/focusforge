import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'theme/glass_theme.dart';

/// Theme selection lives in a tiny value notifier so the Profile screen can
/// flip it without pulling in a state-management package.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);

class FocusForgeApp extends StatelessWidget {
  const FocusForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'FocusForge',
        debugShowCheckedModeBanner: false,
        theme: GlassTheme.light(),
        darkTheme: GlassTheme.dark(),
        themeMode: mode,
        home: const AppShell(),
      ),
    );
  }
}
