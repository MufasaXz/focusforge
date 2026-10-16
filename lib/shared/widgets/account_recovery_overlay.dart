import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/services/auth_service.dart';

/// One app-level surface for email, Google and restored SDK sessions.
class AccountRecoveryOverlay extends StatelessWidget {
  const AccountRecoveryOverlay({
    super.key,
    required this.service,
    required this.child,
  });
  final AuthService service;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AccountRecoveryStage?>(
    valueListenable: service.recoveryState,
    builder: (context, stage, _) {
      final cs = Theme.of(context).colorScheme;
      return Stack(
        children: [
          child,
          if (stage != null) ...[
            const ModalBarrier(dismissible: false, color: Color(0x66000000)),
            Center(
              child: Semantics(
                liveRegion: true,
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: context.tr('Restoring your account'),
                child: Material(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            context.tr('Restoring your account'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.tr(
                              stage == AccountRecoveryStage.retrying
                                  ? 'Reconnecting to your saved data…'
                                  : 'Recovering your goals, subjects and focus history…',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}
