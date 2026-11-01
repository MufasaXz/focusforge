import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/usage_providers.dart';

/// The prominent disclosure for the installed-app list and per-app usage.
///
/// Google Play's User Data policy asks for this wording shape — what the app
/// collects, to enable which feature, in what scenario — and for it to say
/// plainly where the data goes. Kept to that one subject: it is not folded
/// into the accessibility or usage-access explanations, which describe other
/// access.
String appListDisclosureText(BuildContext context) => context.tr(
  "FocusForge reads the list of apps installed on this phone, and how long you used each one today, to let you choose apps to block or limit in Shield and to show your screen time on Home. This happens only while you use those screens.\n\nThe app list and usage times stay on this device. FocusForge does not upload, store on a server, or share them with anyone — not with study groups, the leaderboard or your account backup.\n\nYou can withdraw this at any time in Profile → Privacy. Focus timers work without it.",
);

/// Asks once, in a dialog, before anything reads the app list.
///
/// True when the user has already agreed or taps Agree now. The dialog cannot
/// be dismissed by tapping outside it, and Back or "Not now" answers false:
/// leaving the disclosure is never taken as consent.
Future<bool> confirmAppListAccess(BuildContext context, WidgetRef ref) async {
  if (ref.read(appListConsentProvider)) return true;
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.apps_rounded),
      title: Text(context.tr("Allow FocusForge to read your app list?")),
      scrollable: true,
      content: Text(appListDisclosureText(context)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr("Not now")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr("Agree")),
        ),
      ],
    ),
  );
  if (agreed != true) return false;
  await ref.read(appListConsentProvider.notifier).set(true);
  return true;
}

/// The same disclosure, inline, where the app list would otherwise be.
///
/// Shown on the Shield tab in normal use, not behind a menu, so the user meets
/// it the first time they go to pick an app. Nothing is read until Agree.
class AppListDisclosureCard extends ConsumerWidget {
  const AppListDisclosureCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apps_rounded, color: cs.primary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  context.tr("Allow FocusForge to read your app list?"),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            appListDisclosureText(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: () =>
                  ref.read(appListConsentProvider.notifier).set(true),
              child: Text(context.tr("Agree")),
            ),
          ),
        ],
      ),
    );
  }
}
