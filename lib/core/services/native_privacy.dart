import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only app-owned native preferences and temporary files; SDK credentials are
/// removed through their own sign-out APIs, never copied into an export.
class NativePrivacy {
  static const _channel = MethodChannel('dev.focusforge/privacy');
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<Map<String, dynamic>> export() async {
    if (!_supported) return {};
    try {
      return Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>('export') ?? {},
      );
    } on MissingPluginException {
      return {}; // Platforms and widget-test hosts without the Android bridge.
    }
  }

  static Future<void> erase() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('erase');
    } on MissingPluginException {
      // No native stores exist on hosts without this platform bridge.
    }
  }
}
