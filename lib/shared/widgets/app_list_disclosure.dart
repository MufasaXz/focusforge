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
///
/// One lead sentence in the policy's own shape, then three short points, so
/// the part a person actually reads is the part that matters. The same body is
/// used by the dialog, the Shield card and the setup step, so the three can
/// never describe the access differently.
class AppListDisclosureBody extends StatelessWidget {
  const AppListDisclosureBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            "FocusForge reads the list of apps installed on this phone and how long you used each one today, to let you choose apps to block or limit in Shield and to show your screen time on Home.",
          ),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: Gap.lg),
        _Point(
          icon: Icons.phone_android_rounded,
          title: context.tr("Stays on this phone"),
          body: context.tr(
            "Never uploaded, stored on a server or shared — not with study groups, the leaderboard or your backup.",
          ),
        ),
        _Point(
          icon: Icons.touch_app_outlined,
          title: context.tr("Only after you agree"),
          body: context.tr(
            "Nothing is read before you tap Agree, and only while you use Shield or Home.",
          ),
        ),
        _Point(
          icon: Icons.tune_rounded,
          title: context.tr("You stay in control"),
          body: context.tr(
            "Withdraw anytime in You → Account & privacy. Focus timers work without it.",
          ),
          last: true,
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      content: const AppListDisclosureBody(),
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
                child: Semantics(
                  header: true,
                  child: Text(
                    context.tr("Allow FocusForge to read your app list?"),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          const AppListDisclosureBody(),
          const SizedBox(height: Gap.lg),
          SizedBox(
            width: double.infinity,
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
