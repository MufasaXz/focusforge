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

  /// Lets [packageId] through for [seconds] — the "open it anyway" path.
  ///
  /// A no-op where there is no engine to tell, so the caller never has to
  /// branch on the platform to offer the option.
  Future<void> grantTemporaryAccess(String packageId, {required int seconds});

  /// Brings [packageId] back to the front — the second half of "open it
  /// anyway".
  ///
  /// The pause is spent inside FocusForge, so by the time it ends the app the
  /// user asked for is no longer on screen. Granting the grace is not enough
  /// on its own; something has to put the app back, and the engine is the only
  /// side that can resolve a package to a launchable activity.
  Future<void> openApp(String packageId);
}

/// A launch the block screen sent us.
///
/// The service covers an app, the user chooses to go in anyway, and FocusForge
/// is started with the package it was covering plus the grace that decision
/// buys. Passing the grace through the intent rather than re-reading it here is
/// what keeps the two sides from disagreeing about how long the user has.
class BlockedLaunch {
  const BlockedLaunch({
    required this.packageId,
    required this.label,
    required this.graceSeconds,
  });

  final String packageId;
  final String label;
  final int graceSeconds;
}

/// The complete desired shield state.
///
/// One list of tiers plus the YouTube surfaces. There is deliberately no
/// separate rule type: a rule is a tier plus a package id, and deriving it
/// here rather than storing it means the Shield screen and the engine cannot
/// drift apart about what is armed.
class ShieldConfig {
  const ShieldConfig({
    required this.whitelist,
    required this.youtube,
    this.strictMode = const StrictModeConfig(),
    this.graceSeconds = defaultGraceSeconds,
  });

  /// How long "open it anyway" buys, in seconds.
  ///
  /// Longer than the pause that precedes it, deliberately. The breath exercise
  /// is 57 seconds; a window shorter than that would spend itself before the
  /// user had read a single thing in the app they chose to open, and being
  /// covered again that fast reads as a bug rather than as a rule.
  static const defaultGraceSeconds = 300;

  final List<WhitelistEntry> whitelist;
  final YoutubeRules youtube;
  final StrictModeConfig strictMode;
  final int graceSeconds;

  /// Everything the native side needs, and nothing else.
  ///
  /// Keyed by Android package name, because that is the only identifier the
  /// accessibility service can match against — an internal row id would be a
  /// rule the engine has no way to recognise. Entries with no package, or in
  /// the always-allowed tier, produce no rule at all rather than one that
  /// silently does nothing.
  Map<String, dynamic> toChannelPayload() => {
    'apps': {
      for (final e in whitelist)
        if (e.packageId != null && e.tier.isEnforced)
          e.packageId!: {
            'label': e.name,
            'mode': e.tier == WhitelistTier.budgeted ? 'budget' : 'block',
            'budgetMinutes': e.budgetMinutes ?? 0,
          },
    },
    'youtube': youtube.toJson(),
    // Strict mode is passed as a deadline rather than a duration: the engine
    // has no idea when the window opened, and computing it here means the two
    // sides cannot disagree about whether it is still running.
    'strictUntil': strictMode.endsAt?.millisecondsSinceEpoch,
    'graceSeconds': graceSeconds,
  };
}

/// A single blocked-app launch, as reported by the native service.
class ShieldInterception {
  const ShieldInterception({
    required this.appName,
    required this.packageId,
    required this.at,
    this.walkedAway = true,
  });

  final String appName;
  final String packageId;
  final DateTime at;

  /// True when the user took the offered way out rather than going in. This is
  /// the only number that can say whether the block is working — a block that
  /// is dismissed every time is a speed bump, not a shield.
  final bool walkedAway;
}

/// Stands in for the native engine everywhere there is no accessibility
/// service to talk to — the browser preview, tests, and any non-Android build.
///
/// It remembers the last config it was handed and logs the hand-off calls, so
/// the shield layer is fully exercisable — and inspectable — without a device.
/// Nothing here pretends to actually block anything.
class RecordingShieldService implements ShieldPlatformService {
  ShieldConfig? lastApplied;

  /// Every call this service was handed, in order, as
  /// `grant:<package>@<seconds>` or `open:<package>`.
  ///
  /// The order is the point. The grace has to be granted before the app is
  /// brought forward, or the block screen the user just sat through comes back
  /// the moment the app opens.
  final calls = <String>[];

  final _interceptions = StreamController<ShieldInterception>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => false;

  @override
  Future<void> requestPermission() async {
    // There is no settings page to open, and nothing to enable.
  }

  @override
  Future<void> applyConfig(ShieldConfig config) async {
    lastApplied = config;
  }

  @override
  Future<void> grantTemporaryAccess(
    String packageId, {
    required int seconds,
  }) async {
    // Nothing is being blocked, so there is nothing to let through — but the
    // call itself is the thing under test.
    calls.add('grant:$packageId@$seconds');
  }

  @override
  Future<void> openApp(String packageId) async {
    // There is no launcher to ask and no app to bring forward.
    calls.add('open:$packageId');
  }

  @override
  Stream<ShieldInterception> get interceptions => _interceptions.stream;

  void dispose() => _interceptions.close();
}
