import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
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
  static const _version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return GlassPage(
      title: 'About',
      subtitle: 'FocusForge v$_version',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPanel(
            radius: Radii.hero,
            blur: 18,
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              children: [
                GlassIconBadge(
                  icon: Icons.local_fire_department_rounded,
                  color: t.accentPrimary,
                  size: 72,
                  radius: 24,
                  glow: 0.6,
                ),
                const SizedBox(height: Gap.lg),
                Text('FocusForge', style: context.type.headlineMedium),
                const SizedBox(height: Gap.xs),
                Text('Version $_version', style: context.type.labelSmall),
                const SizedBox(height: Gap.lg),
                GlassPill(
                  selected: true,
                  accent: t.success,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 13,
                        color: t.success,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Free and open source',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                Text(
                  'MIT licensed. The whole app lives on GitHub — the shield '
                  'rules, the Pomodoro engine and the glass you are looking at.',
                  textAlign: TextAlign.center,
                  style: context.type.bodySmall?.copyWith(
                    color: t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          GlassSection(
            title: 'Links',
            footnote:
                'Links are copied to the clipboard — paste them into a '
                'browser.',
            children: [
              GlassRow(
                title: 'Star on GitHub',
                subtitle: 'github.com/MufasaXz/focusforge',
                icon: Icons.code_rounded,
                trailing: const _CopyGlyph(),
                onTap: () => _copy(context, _repoUrl, 'Repository link'),
              ),
              GlassRow(
                title: 'Report a bug',
                subtitle: 'Open an issue on GitHub',
                icon: Icons.bug_report_rounded,
                trailing: const _CopyGlyph(),
                showDivider: false,
                onTap: () => _copy(context, _issuesUrl, 'Bug report link'),
              ),
            ],
          ),
          GlassSection(
            title: 'Credits',
            children: [
              const GlassRow(
                title: 'Built with Flutter',
                subtitle: 'Interface, engine and glass design system',
                icon: Icons.flutter_dash,
              ),
              GlassRow(
                title: 'Ambient audio',
                subtitle: 'Six CC0 loops from freesound.org',
                icon: Icons.graphic_eq_rounded,
                trailing: const GlassChevron(),
                onTap: () => _showAudioCredits(context),
              ),
              const GlassRow(
                title: 'Typeface',
                subtitle: 'Inter and Inter Display, SIL Open Font License',
                icon: Icons.text_fields_rounded,
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Legal',
            children: [
              GlassRow(
                title: 'MIT licence',
                subtitle: 'Use, modify and redistribute freely',
                icon: Icons.balance_rounded,
                trailing: const GlassChevron(),
                onTap: () => _showMit(context),
              ),
              GlassRow(
                title: 'Open source licences',
                subtitle: 'Every bundled package and asset',
                icon: Icons.article_rounded,
                trailing: const GlassChevron(),
                showDivider: false,
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
                  style: context.type.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'v$_version · MIT',
                  style: context.type.labelSmall?.copyWith(
                    fontSize: 10.5,
                    color: t.textTertiary,
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
    showGlassSnack(context, '$label copied to the clipboard.');
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
    showGlassDialog<void>(
      context: context,
      builder: (context) => const _TextBody(
        title: 'MIT licence',
        body: _mitText,
        scrollable: true,
      ),
    );
  }

  void _showAudioCredits(BuildContext context) {
    showGlassDialog<void>(
      context: context,
      builder: (context) => const _AudioCreditsBody(),
    );
  }
}

class _CopyGlyph extends StatelessWidget {
  const _CopyGlyph();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.copy_rounded, size: 17, color: context.glass.textTertiary);
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
    final t = context.glass;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassIconBadge(
              icon: Icons.graphic_eq_rounded,
              color: t.accentSecondary,
              size: 40,
              radius: 12,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text('Ambient audio', style: context.type.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        for (final (title, author) in _tracks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.type.bodyMedium)),
                Text(
                  author,
                  style: context.type.labelSmall?.copyWith(
                    color: t.textTertiary,
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
          style: context.type.bodySmall?.copyWith(color: t.textTertiary),
        ),
        const SizedBox(height: Gap.xl),
        GlassActionButton(
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
    final t = context.glass;
    final text = Text(
      body,
      style: context.type.bodySmall?.copyWith(height: 1.5),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassIconBadge(
              icon: Icons.balance_rounded,
              color: t.accentPrimary,
              size: 40,
              radius: 12,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(title, style: context.type.titleMedium)),
          ],
        ),
        const SizedBox(height: Gap.lg),
        if (scrollable)
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.item),
              color: t.glassL2At(0.45),
              border: Border.all(color: t.glassL2Border),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.md),
              child: text,
            ),
          )
        else
          text,
        const SizedBox(height: Gap.xl),
        GlassActionButton(
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
