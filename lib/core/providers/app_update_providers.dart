import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_update_service.dart';
import 'app_providers.dart';
import 'study_providers.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => AppUpdateService(
    ref.watch(localStoreProvider),
    enabled: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  ),
);

final appUpdatePromptAllowedProvider = Provider<bool>(
  (ref) =>
      ref.watch(userProvider.select((u) => u.onboardingComplete)) &&
      !ref.watch(timerProvider.select((t) => t.running)) &&
      !ref.watch(accountMutationProvider),
);
