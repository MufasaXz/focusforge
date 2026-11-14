import 'package:flutter/material.dart';

import '../../../core/models/user.dart';
import '../../onboarding/auth_screen.dart';

/// The same account screen as onboarding, retaining the guest-link contract.
Future<UserProfile?> showLinkAccountSheet(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<UserProfile>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) =>
          AuthScreen(onLinked: (profile) => Navigator.of(context).pop(profile)),
    ),
  );
}
