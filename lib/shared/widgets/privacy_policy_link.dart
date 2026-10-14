import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://focusforgeorg.vercel.app/privacy';
const accountDeletionUrl = 'https://focusforgeorg.vercel.app/delete-account';

/// Open the public policy directly; retain a usable link without a browser.
Future<void> openPrivacyResource(BuildContext context, String url) async {
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } on PlatformException {
    // A missing handler is recoverable through the clipboard below.
  } on MissingPluginException {
    // Unsupported embeddings can still expose the public URL.
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Could not open a browser. Link copied; paste it into your browser.',
      ),
    ),
  );
}

class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => openPrivacyResource(context, privacyPolicyUrl),
    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
    label: const Text('Privacy policy'),
  );
}
