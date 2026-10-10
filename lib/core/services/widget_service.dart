import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The launcher widget uses persisted data and the native countdown clock.
class WidgetService {
  const WidgetService._();
  static bool enabled = false;
  static const _channel = MethodChannel('focusforge/widgets');

  static bool get _supported =>
      enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> refresh() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Widget tests and unsupported embeddings have no Android host.
    } on PlatformException {
      // A launcher failure must never prevent saving a completed session.
    }
  }

  static Future<bool> takeFocusLaunch() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('takeFocusLaunch') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
