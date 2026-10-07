import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import 'settings_support.dart';

/// About FocusForge.
///
/// The outbound links copy to the clipboard rather than launching a browser:
/// opening a URL needs a platform plugin, and one plugin for two links is not
/// worth the dependency. The row's trailing icon and the section footnote say
/// so, so the tap is not a surprise.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _repoUrl = 'https://github.com/MufasaXz/focusforge';
  static const _issuesUrl = 'https://github.com/MufasaXz/focusforge/issues/new';

  /// Kept in step with `pubspec.yaml` by hand. There is no `package_info`
  /// dependency by design, and one hardcoded string is cheaper than a plugin.
  static const _version = '1.0.2';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppPage(
      title: 'About',
      subtitle: 'FocusForge v$_version',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                children: [
                  IconBadge(
                    icon: Icons.local_fire_department_rounded,
                    color: cs.primary,
                    size: 72,
                    radius: 24,
                  ),
                  const SizedBox(height: Gap.lg),
                  Text('FocusForge', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: Gap.xs),
                  Text('Version $_version', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Gap.lg),
                  Chip(
                    avatar: Icon(
                      Icons.verified_user_rounded,
                      size: 18,
                      color: cs.tertiary,
                    ),
                    label: const Text('Free and open source'),
                  ),
                  const SizedBox(height: Gap.md),
                  Text(
                    'MIT licensed. The whole app lives on GitHub — the shield '
                    'rules, the Pomodoro engine and the interface you are '
                    'looking at.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xl),
          AppSection(
            title: 'Links',
            footnote:
                'Links are copied to the clipboard — paste them into a '
                'browser.',
            children: [
              ListTile(
                title: const Text('Star on GitHub'),
                subtitle: const Text('github.com/MufasaXz/focusforge'),
                leading: const Icon(Icons.code),
                trailing: const _CopyGlyph(),
                onTap: () => _copy(context, _repoUrl, 'Repository link'),
              ),
              ListTile(
                title: const Text('Report a bug'),
                subtitle: const Text('Open an issue on GitHub'),
                leading: const Icon(Icons.bug_report_outlined),
                trailing: const _CopyGlyph(),
                onTap: () => _copy(context, _issuesUrl, 'Bug report link'),
              ),
            ],
          ),
          AppSection(
            title: 'Credits',
            children: [
              const ListTile(
                title: Text('Built with Flutter'),
                subtitle: Text('Interface, engine and Material 3 design system'),
                leading: Icon(Icons.flutter_dash),
              ),
              ListTile(
                title: const Text('Ambient audio'),
                subtitle: const Text('Six CC0 loops from freesound.org'),
                leading: const Icon(Icons.graphic_eq),
                trailing: const AppChevron(),
                onTap: () => _showAudioCredits(context),
              ),
              const ListTile(
                title: Text('Typeface'),
                subtitle: Text('Inter and Inter Display, SIL Open Font License'),
                leading: Icon(Icons.text_fields),
              ),
            ],
          ),
          AppSection(
            title: 'Legal',
            children: [
              ListTile(
                title: const Text('MIT licence'),
                subtitle: const Text('Use, modify and redistribute freely'),
                leading: const Icon(Icons.balance_outlined),
                trailing: const AppChevron(),
                onTap: () => _showMit(context),
              ),
              ListTile(
                title: const Text('Open source licences'),
                subtitle: const Text('Every bundled package and asset'),
                leading: const Icon(Icons.article_outlined),
                trailing: const AppChevron(),
                onTap: () => _showLicences(context),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Column(
              children: [
                Text(
                  'Made by the FocusForge community',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'v$_version · MIT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
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

  Future<void> _copy(BuildContext context, String url, String label) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    showAppSnack(context, '$label copied to the clipboard.');
  }

  void _showLicences(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'FocusForge',
      applicationVersion: _version,
      applicationLegalese: 'MIT licensed · built with Flutter',
    );
  }

  void _showMit(BuildContext context) {
    showAppDialog<void>(
      context: context,
      builder: (context) => const _TextBody(
        title: 'MIT licence',
        body: _mitText,
        scrollable: true,
      ),
    );
  }

  void _showAudioCredits(BuildContext context) {
    showAppDialog<void>(
      context: context,
      builder: (context) => const _AudioCreditsBody(),
    );
  }
}

class _CopyGlyph extends StatelessWidget {
  const _CopyGlyph();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.copy_outlined, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant);
}

class _AudioCreditsBody extends StatelessWidget {
  const _AudioCreditsBody();

  static const _tracks = <(String, String)>[
    ('Rain', 'unfa'),
    ('Forest', 'hargissssound'),
    ('Café', 'priesjensen'),
    ('Waves', 'SamsterBirdies'),
    ('Fireplace', 'BonnyOrbit'),
    ('Brown Noise', 'tracyradio'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: Icons.graphic_eq_rounded,
              color: cs.secondary,
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text('Ambient audio', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        for (final (title, author) in _tracks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyMedium)),
                Text(
                  author,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.md),
        Text(
          'All six loops are CC0 1.0 (public domain) and were sourced from '
          'freesound.org. Credit is given here although the licence does not '
          'require it.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.xl),
        AppActionButton(
          label: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _TextBody extends StatelessWidget {
  const _TextBody({
    required this.title,
    required this.body,
    this.scrollable = false,
  });

  final String title;
  final String body;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      body,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: Icons.balance_rounded,
              color: cs.primary,
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: Gap.lg),
        if (scrollable)
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.item),
              color: cs.surfaceContainerHigh,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.md),
              child: text,
            ),
          )
        else
          text,
        const SizedBox(height: Gap.xl),
        AppActionButton(
          label: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

const _mitText =
    'Copyright (c) 2026 The FocusForge contributors\n\n'
    'Permission is hereby granted, free of charge, to any person obtaining a '
    'copy of this software and associated documentation files (the '
    '“Software”), to deal in the Software without restriction, including '
    'without limitation the rights to use, copy, modify, merge, publish, '
    'distribute, sublicense, and/or sell copies of the Software, and to permit '
    'persons to whom the Software is furnished to do so, subject to the '
    'following conditions:\n\n'
    'The above copyright notice and this permission notice shall be included '
    'in all copies or substantial portions of the Software.\n\n'
    'THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS '
    'OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
    'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. '
    'IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY '
    'CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT '
    'OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR '
    'THE USE OR OTHER DEALINGS IN THE SOFTWARE.';
