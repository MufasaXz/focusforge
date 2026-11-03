import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/usage_providers.dart';

/// The prominent disclosure for the installed-app list and per-app usage.
///
/// Google Play's User Data policy asks it to say what is read, for which
/// feature, and where the data goes, before anything is read and in the normal
/// flow of the app. Four short rows answer exactly those questions, so the part
/// a person actually reads is the part that matters. The same body is used by
/// the dialog, the Shield card and the setup step, so the three can never
/// describe the access differently. It covers this one access only; Usage
/// access settings, overlay and Accessibility are explained where they are
/// asked for.
class AppListDisclosureBody extends StatelessWidget {
  const AppListDisclosureBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Point(
          icon: Icons.apps_rounded,
          title: context.tr("What FocusForge reads"),
          body: context.tr(
            "The apps installed on this phone and how long you used each one today.",
          ),
        ),
        _Point(
          icon: Icons.timer_outlined,
          title: context.tr("Why"),
          body: context.tr(
            "To let you block or limit apps in Shield and show your screen time on Home.",
          ),
        ),
        _Point(
          icon: Icons.phone_android_rounded,
          title: context.tr("Where it goes"),
          body: context.tr(
            "Nowhere. It stays on this phone and is never uploaded or shared.",
          ),
        ),
        _Point(
          icon: Icons.toggle_on_outlined,
          title: context.tr("Your choice"),
          body: context.tr(
            "Nothing is read until you agree. Turn it off anytime in You → Account & privacy.",
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
      padding: EdgeInsets.only(bottom: last ? 0 : Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
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
      icon: const Icon(Icons.shield_outlined),
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
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined, color: cs.primary),
          ),
          const SizedBox(height: Gap.md),
          Semantics(
            header: true,
            child: Text(
              context.tr("Allow FocusForge to read your app list?"),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          const AppListDisclosureBody(),
          const SizedBox(height: Gap.xl),
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
