import 'dart:async';

import '../models/shield.dart';

/// The contract between the app and the native shielding engine.
///
/// The UI never talks to a `MethodChannel` directly. It calls this, which means
/// the Android `AccessibilityService` / iOS `FamilyControls` implementation can
/// land later without touching a single widget — and that the whole shield
/// layer is testable today against [RecordingShieldService].
abstract class ShieldPlatformService {
  /// Whether the OS-level service is installed and enabled by the user.
  Future<bool> isServiceEnabled();

  /// Opens the system settings page where the user grants access.
  Future<void> requestPermission();

  /// Pushes the complete desired state down to the native side. Called after
  /// every mutation rather than sending deltas — the native engine should be
  /// able to rebuild its world from one payload, which makes it impossible for
  /// the two sides to drift apart.
  Future<void> applyConfig(ShieldConfig config);

  /// Fires when the native side reports an interception. Feeds the Deep Breath
  /// Gate and the impulse-event log.
  Stream<ShieldInterception> get interceptions;
}

/// The complete desired shield state.
class ShieldConfig {
  const ShieldConfig({
    required this.feedShields,
    required this.whitelist,
    required this.activeProfileId,
    required this.strictMode,
  });

  final List<FeedRow> feedShields;
  final List<WhitelistEntry> whitelist;
  final String? activeProfileId;
  final StrictModeConfig strictMode;

  /// Everything the native side needs, and nothing else. Kept as a plain map
  /// so it crosses a channel without a codec.
  Map<String, dynamic> toChannelPayload() => {
        'feeds': {
          for (final f in feedShields)
            f.id: {'enabled': f.enabled, 'mode': f.mode.name},
        },
        'whitelist': {
          for (final w in whitelist)
            w.id: {
              'tier': w.tier.name,
              'budgetMinutes': w.budgetMinutes,
            },
        },
        'activeProfileId': activeProfileId,
        'strictMode': strictMode.toJson(),
      };
}

/// A single blocked-app launch, as reported by the native service.
class ShieldInterception {
  const ShieldInterception({
    required this.appName,
    required this.packageId,
    required this.at,
  });

  final String appName;
  final String packageId;
  final DateTime at;
}

/// Stands in for the native engine until Phase 2.
///
/// It remembers the last config it was handed and exposes it, so the shield
/// layer is fully exercisable — and inspectable — in the browser preview and in
/// tests. Nothing here pretends to actually block anything.
class RecordingShieldService implements ShieldPlatformService {
  ShieldConfig? lastApplied;

  final _interceptions = StreamController<ShieldInterception>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => false;

  @override
  Future<void> requestPermission() async {
    // Phase 2: launch the Accessibility settings intent.
  }

  @override
  Future<void> applyConfig(ShieldConfig config) async {
    lastApplied = config;
  }

  @override
  Stream<ShieldInterception> get interceptions => _interceptions.stream;

  /// Test/preview hook — lets the Deep Breath Gate be demonstrated without the
  /// native service present.
  void simulate(String appName, {String packageId = 'com.example.app'}) {
    _interceptions.add(
      ShieldInterception(
        appName: appName,
        packageId: packageId,
        at: DateTime.now(),
      ),
    );
  }

  void dispose() => _interceptions.close();
}
