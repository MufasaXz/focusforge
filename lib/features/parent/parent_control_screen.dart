import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/parent.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/services/parent_service.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../settings/settings_support.dart';
import 'parent_lock.dart';

/// Parent control — one page, two roles.
///
/// A device is either watched by a parent or it is a parent's own. Which one
/// this is decides the order of the page, not its contents: the linking card
/// first on a child's phone, the children first on a parent's. Keeping both
/// halves on one page means a parent who set their own device up as "for me"
/// can still pair a child later without hunting for a second screen.
class ParentControlScreen extends ConsumerWidget {
  const ParentControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(parentServiceProvider).available;
    final guardian = ref.watch(guardianProvider).value;
    final isGuardian = ref.watch(userProvider).isGuardian;

    return AppPage(
      title: 'Parent control',
      subtitle: guardian != null
          ? 'Watched by ${guardian.name}'
          : isGuardian
          ? 'Watch a child\'s study'
          : 'Pairing and the security code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!available) ...[
            const _NoBackendCard(),
            const SizedBox(height: Gap.xl),
          ],
          // The role the device was set up for comes first. Both sections stay
          // reachable either way; this is about which question is answered
          // before the user has to scroll.
          if (isGuardian || guardian == null) ...[
            _ChildrenSection(enabled: available),
            _ThisDeviceSection(enabled: available),
          ] else ...[
            const _ThisDeviceSection(enabled: true),
            _ChildrenSection(enabled: available),
          ],
          const _WhatATParentSeesNote(),
        ],
      ),
    );
  }
}

/// Shown when Firebase did not start: the pairing cannot work and the page
/// says so instead of offering a button that fails.
class _NoBackendCard extends StatelessWidget {
  const _NoBackendCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'This build has no backend to pair over, so parent control is '
                'unavailable. Everything else in the app works as usual.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- This device -------------------------------------------------------------

/// Whether this device is watched, and the code that guards turning it off.
class _ThisDeviceSection extends ConsumerWidget {
  const _ThisDeviceSection({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardian = ref.watch(guardianProvider).value;
    final hasCode = ref.watch(securityCodeProvider);

    return AppSection(
      title: 'This device',
      footnote: guardian == null
          ? 'A parent types the code into their own phone. Nothing is shared '
                'until they do.'
          : hasCode
          ? 'The code is asked for before anything here is turned off.'
          : 'No security code is set. Anyone holding this device can turn '
                'parent control off.',
      children: [
        if (guardian == null)
          ListTile(
            leading: const IconBadge(
              icon: Icons.qr_code_2_rounded,
              color: Color(0xFF7FA9FF),
            ),
            title: const Text('Show this device\'s code'),
            subtitle: const Text('Six digits, good for 15 minutes'),
            enabled: enabled,
            onTap: enabled
                ? () => unawaited(_showPairCode(context, ref))
                : null,
          )
        else ...[
          ListTile(
            leading: const IconBadge(
              icon: Icons.family_restroom_rounded,
              color: Color(0xFF8FE39B),
            ),
            title: Text(guardian.name),
            subtitle: Text(
              guardian.linkedAt == null
                  ? 'Linked to this device'
                  : 'Linked on ${_day(guardian.linkedAt!)}',
            ),
          ),
          if (hasCode)
            ListTile(
              leading: const IconBadge(
                icon: Icons.lock_rounded,
                color: Color(0xFFFFD08A),
              ),
              title: const Text('Security code is on'),
              subtitle: const Text('Change or remove it'),
              onTap: () => unawaited(_changeSecurityCode(context, ref)),
            )
          else
            ListTile(
              leading: const IconBadge(
                icon: Icons.lock_open_rounded,
                color: Color(0xFFFFD08A),
              ),
              title: const Text('Set a security code'),
              subtitle: const Text('Optional — stops it being turned off'),
              onTap: () => unawaited(_setSecurityCode(context, ref)),
            ),
          ListTile(
            leading: Icon(
              Icons.link_off_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Turn off parent control',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Unlinks this device and lifts their rules'),
            onTap: () => unawaited(_turnOff(context, ref, guardian)),
          ),
        ],
      ],
    );
  }
}

/// Mints a code, shows it, and waits for the parent to claim it.
///
/// The wait is the point: the code is read off this screen and typed into
/// another phone, and a dialog that closed on minting would leave the user
/// wondering whether it worked.
Future<void> _showPairCode(BuildContext context, WidgetRef ref) async {
  final service = ref.read(parentServiceProvider);
  final name = ref.read(userProvider).displayName;

  final PairCode code;
  try {
    code = await service.mintPairCode(childName: name);
  } on PairException catch (error) {
    if (context.mounted) showAppSnack(context, error.friendly);
    return;
  }
  if (!context.mounted) return;

  await showAppDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _PairCodeBody(code: code),
  );
}

class _PairCodeBody extends ConsumerWidget {
  const _PairCodeBody({required this.code});

  final PairCode code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // The link is written by the *other* phone, so this screen finds out the
    // same way the rest of the app does.
    final guardian = ref.watch(guardianProvider).value;

    ref.listen(guardianProvider, (previous, next) {
      final link = next.value;
      if (link == null) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Linked to ${link.name}.');
    });

    if (guardian != null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const IconBadge(
              icon: Icons.qr_code_2_rounded,
              color: Color(0xFF7FA9FF),
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'Your pairing code',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Type this into the parent\'s phone, in Parent control → Add a '
          'child.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.lg),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Gap.lg),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radii.item),
          ),
          child: Text(
            code.code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              letterSpacing: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Good for ${PairCode.lifetime.inMinutes} minutes, and only once.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.xl),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Turns the link off. Behind the security code when one is set.
Future<void> _turnOff(
  BuildContext context,
  WidgetRef ref,
  GuardianLink guardian,
) async {
  if (!await confirmParentUnlock(
    context,
    ref,
    message:
        'Enter the code a parent set to unlink this device from '
        '${guardian.name}.',
  )) {
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showAppConfirmDialog(
    context: context,
    title: 'Turn off parent control?',
    message:
        '${guardian.name} will stop seeing this device\'s study summary, and '
        'the blocks they set will lift.',
    confirmLabel: 'Turn off',
    destructive: true,
    icon: Icons.link_off_rounded,
  );
  if (!confirmed) return;

  final service = ref.read(parentServiceProvider);
  final uid = ref.read(accountUidProvider);
  if (uid == null) return;
  try {
    await service.unlink(uid);
    // The parent's rules are gone at the source; clear them here too, so the
    // engine stops enforcing them on the next push rather than waiting for a
    // stream that will never deliver.
    ref.read(remoteBlocksProvider.notifier).set(const RemoteBlocks());
    ref.read(parentLockProvider.notifier).lock();
    if (context.mounted) {
      showAppSnack(context, 'Parent control is off.');
    }
  } on PairException catch (error) {
    if (context.mounted) showAppSnack(context, error.friendly);
  }
}

// -- The security code -------------------------------------------------------

Future<void> _setSecurityCode(BuildContext context, WidgetRef ref) async {
  final code = await showAppInputDialog(
    context: context,
    title: 'Set a security code',
    message:
        'Ask a parent to type a code only they know. It is asked for before '
        'parent control is turned off, and before the shield rules change.',
    actionLabel: 'Set code',
    hintText: 'At least 4 digits',
    icon: Icons.lock_rounded,
    keyboardType: TextInputType.number,
    footnote:
        'A speed bump, not a lock: clearing the app\'s data or uninstalling '
        'it removes the code along with everything else.',
  );
  if (code == null) return;
  if (code.length < 4) {
    if (context.mounted) showAppSnack(context, 'Use at least 4 digits.');
    return;
  }
  await ref.read(securityCodeProvider.notifier).set(code);
  if (context.mounted) showAppSnack(context, 'Security code set.');
}

Future<void> _changeSecurityCode(BuildContext context, WidgetRef ref) async {
  final action = await showAppDialog<String>(
    context: context,
    builder: (context) => _SecurityCodeBody(),
  );
  if (action == null || !context.mounted) return;
  if (action == 'remove') {
    await _removeSecurityCode(context, ref);
  } else {
    await _setSecurityCode(context, ref);
  }
}

Future<void> _removeSecurityCode(BuildContext context, WidgetRef ref) async {
  if (!await confirmParentUnlock(
    context,
    ref,
    message: 'Enter the current code to remove it.',
  )) {
    return;
  }
  await ref.read(securityCodeProvider.notifier).clear();
  if (context.mounted) showAppSnack(context, 'Security code removed.');
}

class _SecurityCodeBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const IconBadge(
              icon: Icons.lock_rounded,
              color: Color(0xFFFFD08A),
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'Security code',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Changing or removing the code is itself behind the code.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.lg),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password_rounded),
          title: const Text('Change the code'),
          onTap: () => Navigator.of(context).pop('change'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_open_rounded),
          title: const Text('Remove the code'),
          onTap: () => Navigator.of(context).pop('remove'),
        ),
        const SizedBox(height: Gap.md),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// -- Children ----------------------------------------------------------------

/// The parent's list. Empty on a child's device, which is the normal case.
class _ChildrenSection extends ConsumerWidget {
  const _ChildrenSection({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider).value ?? const <ChildLink>[];
    final loading = ref.watch(childrenProvider).isLoading;

    return AppSection(
      title: 'Children',
      footnote: children.length >= 3
          ? 'Three children is the limit.'
          : 'Each child gets their own dashboard and their own block list.',
      children: [
        if (loading && children.isEmpty)
          const ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Looking for linked devices'),
          )
        else if (children.isEmpty)
          ListTile(
            leading: const IconBadge(
              icon: Icons.child_care_rounded,
              color: Color(0xFF8FE39B),
            ),
            title: const Text('No children linked yet'),
            subtitle: const Text('Add one with a code from their phone'),
          )
        else
          for (final child in children)
            ListTile(
              leading: const IconBadge(
                icon: Icons.person_rounded,
                color: Color(0xFF8FE39B),
              ),
              title: Text(child.name),
              subtitle: Text(
                child.linkedAt == null
                    ? 'Linked'
                    : 'Linked on ${_day(child.linkedAt!)}',
              ),
              trailing: const AppChevron(),
              onTap: () {
                ref.read(selectedChildProvider.notifier).select(child.uid);
                context.pushNamed(
                  AppRoutes.parentChild,
                  pathParameters: {'uid': child.uid},
                );
              },
            ),
        if (children.length < 3)
          ListTile(
            leading: const IconBadge(
              icon: Icons.add_rounded,
              color: Color(0xFF7FA9FF),
            ),
            title: const Text('Add a child'),
            subtitle: const Text('Enter the six digits from their phone'),
            enabled: enabled,
            onTap: enabled ? () => unawaited(_addChild(context, ref)) : null,
          ),
      ],
    );
  }
}

Future<void> _addChild(BuildContext context, WidgetRef ref) async {
  final code = await showAppInputDialog(
    context: context,
    title: 'Add a child',
    message:
        'Open FocusForge on your child\'s phone, go to Profile → Parent '
        'control, and type the six digits it shows.',
    actionLabel: 'Link',
    hintText: 'Six digits',
    icon: Icons.child_care_rounded,
    keyboardType: TextInputType.number,
  );
  if (code == null) return;
  if (!PairCode.looksValid(code)) {
    if (context.mounted) {
      showAppSnack(context, 'A pairing code is six digits.');
    }
    return;
  }

  final service = ref.read(parentServiceProvider);
  final name = ref.read(userProvider).displayName;
  try {
    final child = await service.linkChild(
      code,
      parentName: name.isEmpty ? 'Your parent' : name,
    );
    if (context.mounted) showAppSnack(context, '${child.name} is linked.');
  } on PairException catch (error) {
    if (context.mounted) showAppSnack(context, error.friendly);
  }
}

// -- Notes -------------------------------------------------------------------

class _WhatATParentSeesNote extends StatelessWidget {
  const _WhatATParentSeesNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            'What a parent sees: today\'s minutes, sessions, the daily goal, '
            'the streak and the leading subject. Not the session log, not the '
            'subjects studied, not the apps used.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// A linked date, short: a parent checking who is watching does not need the
/// time of day.
String _day(DateTime at) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${at.day} ${months[at.month - 1]}';
}
