import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/email_auth_sheet.dart';
import '../../../shared/widgets/provider_marks.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Opens the sheet that puts a credential behind a device-only account.
///
/// Returns the profile the credential produced, or null if the user backed
/// out. The sheet runs the sign-in itself rather than handing the choice back:
/// the profile screen only decides *when* it opens, and the one path this
/// branch offers — the email form — is the same one the sign-in screen shows.
/// There is no Google row here because the on-device backend has no OAuth
/// client behind it, and a disabled button that can never become live is an
/// inert control rather than an explanation.
///
/// This is the fix for a card that used to report success on tap. Linking is a
/// sign-in; a button that says "linked" without ever asking for a credential
/// is telling the user something that is not true, and it left study groups
/// and the leaderboard unlocked against an account that did not exist.
Future<UserProfile?> showLinkAccountSheet(BuildContext context) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    backgroundColor: Colors.transparent,
    // The email form inside needs room for the keyboard.
    isScrollControlled: true,
    builder: (_) => const _LinkSheet(),
  );
}

class _LinkSheet extends ConsumerStatefulWidget {
  const _LinkSheet();

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  /// Which row is in flight, so only that one spins.
  String? _busy;

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> _email() async {
    final profile = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EmailAuthSheet(service: _auth),
    );
    if (profile == null || !mounted) return;
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        // The sheet lives under the floating nav bar, so it clears it the same
        // way the profile's scroll view does.
        kNavBarClearance + MediaQuery.paddingOf(context).bottom,
      ),
      child: SheetSurface(
        borderRadius: BorderRadius.circular(Radii.hero),
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.lg),
            Text(
              'Link an account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'Signing in puts a credential behind everything you have logged '
              'here. Nothing on this device is reset, and study groups and the '
              'leaderboard open up.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.lg),
            ProviderRow(
              label: 'Continue with Email',
              leading: const MailMark(),
              busy: _busy == 'email',
              onTap: _email,
            ),
          ],
        ),
      ),
    );
  }
}
