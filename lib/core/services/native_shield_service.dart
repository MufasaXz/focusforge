import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shield_service.dart';

/// Android engines: UsageEvents + application overlay for apps; Accessibility for YouTube filters.
/// Native rules continue while Flutter is paused. Android/OEM restrictions can stop the engines.
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

  /// The app the block screen was covering, if this launch came from one.
  ///
  /// Read once, then cleared natively, so a later resume cannot replay the
  /// pause. Null covers both "this was an ordinary launch" and "the payload
  /// was unusable" — either way there is no interception to act on.
  Future<BlockedLaunch?> takeBlockedApp() async {
    final Map<dynamic, dynamic>? raw;
    try {
      raw = await _methods.invokeMethod<Map<dynamic, dynamic>>('blockedApp');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    if (raw == null) return null;

    final packageId = raw['package'];
    if (packageId is! String || packageId.isEmpty) return null;

    final label = raw['label'];
    final grace = raw['graceSeconds'];

    return BlockedLaunch(
      packageId: packageId,
      label: label is String && label.isNotEmpty ? label : packageId,
      // Zero would mean the pause buys nothing at all, which is the one answer
      // the user could not have intended by choosing to go in anyway.
      graceSeconds: grace is int && grace > 0
          ? grace.clamp(5, 600)
          : ShieldConfig.defaultGraceSeconds,
    );
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

  Future<bool> hasOverlayPermission() => _boolCall('hasOverlayPermission');
  Future<bool> isAppBlockingRunning() => _boolCall('isAppBlockingRunning');
  Future<bool> isAppBlockingPaused() => _boolCall('isAppBlockingPaused');
  Future<bool> resumeAppBlocking() => _boolCall('resumeAppBlocking');
  Future<bool> pauseAppBlocking() => _boolCall('pauseAppBlocking');
  Future<void> requestOverlayPermission() async {
    await _boolCall('openOverlaySettings');
  }

  Future<bool> _boolCall(String method) async {
    try {
      return await _methods.invokeMethod<bool>(method) ?? false;
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
        'seconds': seconds.clamp(5, 600),
      });
    } on PlatformException {
      // The grace is a convenience; failing to grant it must not throw into a
      // caller that is mid-navigation.
    } on MissingPluginException {
      // Not an Android build.
    }
  }

  @override
  Future<void> openApp(String packageId) async {
    try {
      await _methods.invokeMethod<bool>('openApp', {'package': packageId});
    } on PlatformException {
      // The app stays where it is. A hand-off that did not happen is a far
      // better outcome than an exception thrown into a screen that is leaving.
    } on MissingPluginException {
      // Not an Android build.
    }
  }

  @override
  Future<Set<String>> protectedPackages() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>(
        'protectedPackages',
      );
      return {
        for (final entry in raw ?? const <dynamic>[])
          if (entry is String && entry.isNotEmpty) entry,
      };
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      // Not an Android build. An empty set is the honest answer: on a platform
      // with no engine, nothing is protected because nothing is blocked.
      return const {};
    }
  }

  @override
  Future<Set<String>> launchablePackages() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>(
        'launchablePackages',
      );
      return {
        for (final entry in raw ?? const <dynamic>[])
          if (entry is String && entry.isNotEmpty) entry,
      };
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      // Not an Android build, or an older install whose engine predates the
      // method. Empty reads as "could not tell", and the caller keeps its
      // previous filter rather than emptying the list.
      return const {};
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
