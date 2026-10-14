import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/email_verification_panel.dart';

class EmailVerificationScreen extends ConsumerWidget {
  const EmailVerificationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: EmailVerificationPanel(
                service: ref.read(authServiceProvider),
                onVerified: (profile) {
                  ref.read(userProvider.notifier).hydrate(profile);
                  context.goNamed(
                    profile.onboardingComplete
                        ? AppRoutes.dashboard
                        : AppRoutes.onboarding,
                  );
                },
                onSignedOut: () => context.goNamed(AppRoutes.auth),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
