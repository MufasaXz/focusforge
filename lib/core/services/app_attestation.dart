import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Register before Auth/Firestore use. Release builds always use Play Integrity;
/// the debug provider must never be enabled in a distributed release.
Future<void> activateAppAttestation() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
  );
}

/// During the monitoring rollout, unsupported/unregistered installations retain
/// account recovery. Once the servers enforce App Check, missing tokens fail
/// there; this helper cannot bypass enforcement.
Future<String?> appAttestationToken() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await FirebaseAppCheck.instance.getToken().timeout(
      const Duration(seconds: 5),
    );
  } catch (_) {
    return null;
  }
}
