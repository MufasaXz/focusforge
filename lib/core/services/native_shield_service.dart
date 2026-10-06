import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shield_service.dart';

/// The real shield, on Android.
///
/// Everything that has to survive the Flutter engine being paused or killed —
/// matching a package, deciding whether it is blocked, drawing the screen that
/// says so — lives in the native accessibility service. This class is only the
/// wire: config down, interceptions up.
///
/// That split is not an implementation detail. A shield that stops working when
/// the user swipes the app away is not a shield, and a Dart isolate cannot be
/// relied on to be running at the moment a blocked app is launched.
class NativeShieldService implements ShieldPlatformService {
  NativeShieldService();

  static const _methods = MethodChannel('dev.focusforge/shield');
  static const _events = EventChannel('dev.focusforge/shield_events');

  final _interceptions = StreamController<ShieldInterception>.broadcast();

  /// Subscribed once, on the first listener. A second subscription to the same
  /// event channel would register a second native receiver and double every
  /// event.
  StreamSubscription<dynamic>? _subscription;

  /// True when this build can actually block anything.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The package the user chose to open from a block screen, if the app was
  /// launched that way. Read once, then cleared natively.
  Future<Map<String, dynamic>?> takeBlockedApp() async {
    try {
      final raw = await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'blockedApp',
      );
      return raw?.cast<String, dynamic>();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> isServiceEnabled() async {
    try {
      return await _methods.invokeMethod<bool>('isServiceEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _methods.invokeMethod<bool>('openAccessibilitySettings');
    } on PlatformException {
      // Nothing to open. The permission probe reports the truth either way.
    } on MissingPluginException {
      // Not an Android build.
    }
  }

  @override
  Future<void> applyConfig(ShieldConfig config) async {
    try {
      await _methods.invokeMethod<bool>('applyConfig', {
        // Encoded here rather than passed as a map so the native side has
        // exactly one parse path — the same one it uses to read the rules back
        // from disk after a restart.
        'config': jsonEncode(config.toChannelPayload()),
      });
    } on PlatformException {
      // The service picks the rules up from disk on its next start.
    } on MissingPluginException {
      // Not an Android build.
    }
  }

  @override
  Future<void> grantTemporaryAccess(
    String packageId, {
    required int seconds,
  }) async {
    try {
      await _methods.invokeMethod<bool>('grantTemporaryAccess', {
        'package': packageId,
        'seconds': seconds,
      });
    } on PlatformException {
      // The grace is a convenience; failing to grant it must not throw into a
      // caller that is mid-navigation.
    } on MissingPluginException {
      // Not an Android build.
    }
  }

  @override
  Stream<ShieldInterception> get interceptions {
    _subscribe();
    return _interceptions.stream;
  }

  void _subscribe() {
    if (_subscription != null) return;
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      // A channel error is not worth tearing the shield down for; the config
      // side still works and the next event will arrive.
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;

    final packageId = raw['package'];
    if (packageId is! String || packageId.isEmpty) return;

    final label = raw['name'];
    final at = raw['at'];

    _interceptions.add(
      ShieldInterception(
        appName: label is String && label.isNotEmpty ? label : packageId,
        packageId: packageId,
        // A missing or unreadable timestamp falls back to now rather than the
        // epoch: this feeds a rolling log where a 1970 entry would sort to the
        // front and never leave.
        at: at is int
            ? DateTime.fromMillisecondsSinceEpoch(at)
            : DateTime.now(),
        walkedAway: raw['action'] != 'openedAnyway',
      ),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _interceptions.close();
  }
}
