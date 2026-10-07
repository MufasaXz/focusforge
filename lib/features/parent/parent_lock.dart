import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/parent_providers.dart';
import '../settings/settings_support.dart';

/// Asks for the parent's security code before a change that would undo their
/// setup. Returns true when the change may go ahead.
///
/// Every path that changes or removes a rule goes through here rather than
/// each one inventing its own prompt: one question, asked the same way, with
/// one place that decides whether it is needed at all. A device with no linked
/// parent, or a link with no code set, is never asked.
Future<bool> confirmParentUnlock(
  BuildContext context,
  WidgetRef ref, {
  String message =
      'A parent set a code on this device. Enter it to change what the '
      'shield does.',
}) async {
  if (!ref.read(parentLockedProvider)) return true;

  final code = await showAppInputDialog(
    context: context,
    title: 'Parent code',
    message: message,
    actionLabel: 'Unlock',
    hintText: 'The code a parent set',
    icon: Icons.lock_rounded,
    keyboardType: TextInputType.number,
    footnote:
        'This is the code set when the device was linked, not the six-digit '
        'pairing code.',
  );
  if (code == null) return false;

  if (!ref.read(securityCodeProvider.notifier).verify(code)) {
    if (context.mounted) {
      showAppSnack(context, 'That code does not match.');
    }
    return false;
  }
  // Unlocked for this run. Closing the app asks again.
  ref.read(parentLockProvider.notifier).open();
  return true;
}

/// Runs [action] once the parent's code has been cleared, or not at all.
///
/// The shape every rule change uses: the question is asked before the change
/// rather than instead of it, so a refused unlock leaves the rule exactly as
/// it was.
Future<void> runWithParentUnlock(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  if (!await confirmParentUnlock(context, ref)) return;
  await action();
}
