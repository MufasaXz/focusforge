import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/services/widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetService.enabled = true;
  // The app draws small icons, avatars and one guide animation; Flutter's
  // default 100 MB of cached images is far more than it needs.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;

  // Draw behind the system bars. The bar *colours* stay transparent and the
  // icon brightness is set per screen by an AnnotatedRegion in the shell, so
  // it can follow the theme instead of being frozen at startup.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Opens the local store and rehydrates every notifier before the first
  // frame — see bootstrap.dart for why this is not done lazily.
  final container = await bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FocusForgeApp(),
    ),
  );
}
