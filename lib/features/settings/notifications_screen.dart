import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/social_providers.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import 'settings_support.dart';

/// Notification preferences.
///
/// Every switch is one field on [NotificationPrefs], and every switch writes
/// the *whole* updated object through `update(...)`. Persisting the full
/// snapshot — rather than a key per switch — is what lets a future release add
/// a preference without a migration: the stored JSON simply gains a field.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final prefs = ref.watch(notificationsProvider);

    return GlassPage(
      title: 'Notifications',
      subtitle: '${_activeCount(prefs)} of 8 reminders on',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSection(
            title: 'Focus reminders',
            children: [
              _SwitchRow(
                title: 'Session reminders',
                subtitle: '“Time to study Physics!”',
                value: prefs.sessionReminders,
                accent: cs.primary,
                onChanged: (v) =>
                    _save(ref, prefs.copyWith(sessionReminders: v)),
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Progress',
            children: [
              _SwitchRow(
                title: 'Daily summary',
                subtitle: 'Your focus total at the end of the day',
                value: prefs.dailySummary,
                accent: cs.tertiary,
                onChanged: (v) => _save(ref, prefs.copyWith(dailySummary: v)),
              ),
              _SwitchRow(
                title: 'Weekly report',
                subtitle: 'A Sunday recap of the week',
                value: prefs.weeklyReport,
                accent: cs.tertiary,
                onChanged: (v) => _save(ref, prefs.copyWith(weeklyReport: v)),
              ),
              _SwitchRow(
                title: 'Streak risk alerts',
                subtitle: 'A nudge before a streak breaks',
                value: prefs.streakAlerts,
                accent: cs.tertiary,
                onChanged: (v) => _save(ref, prefs.copyWith(streakAlerts: v)),
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Blocking',
            footnote:
                'These fire while a block is active, so they can be '
                'frequent.',
            children: [
              _SwitchRow(
                title: 'Real-time block alerts',
                subtitle: '“Instagram Reels blocked”',
                value: prefs.blockingAlerts,
                accent: cs.error,
                onChanged: (v) => _save(ref, prefs.copyWith(blockingAlerts: v)),
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Social',
            children: [
              _SwitchRow(
                title: 'Study buddy updates',
                subtitle: 'When a buddy starts or finishes a session',
                value: prefs.buddyUpdates,
                accent: cs.secondary,
                onChanged: (v) => _save(ref, prefs.copyWith(buddyUpdates: v)),
              ),
              _SwitchRow(
                title: 'Group activity',
                subtitle: 'Targets met and new members',
                value: prefs.groupActivity,
                accent: cs.secondary,
                onChanged: (v) => _save(ref, prefs.copyWith(groupActivity: v)),
              ),
              _SwitchRow(
                title: 'Challenge invitations',
                subtitle: 'Weekly challenges from friends',
                value: prefs.challengeInvites,
                accent: cs.secondary,
                onChanged: (v) =>
                    _save(ref, prefs.copyWith(challengeInvites: v)),
                showDivider: false,
              ),
            ],
          ),
          GlassSection(
            title: 'Quiet hours',
            footnote: 'Reminders pause during the window; focus timers do not.',
            children: [
              GlassRow(
                title: 'Quiet hours',
                subtitle: prefs.quietHoursEnabled
                    ? 'Muted ${_clock(context, prefs.quietStartHour)} – '
                          '${_clock(context, prefs.quietEndHour)}'
                    : 'Off — notifications arrive at any hour',
                icon: Icons.bedtime_rounded,
                trailing: const GlassChevron(),
                showDivider: false,
                onTap: () => _editQuietHours(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save(WidgetRef ref, NotificationPrefs next) =>
      ref.read(notificationsProvider.notifier).update(next);

  Future<void> _editQuietHours(BuildContext context, WidgetRef ref) async {
    var prefs = ref.read(notificationsProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final cs = Theme.of(context).colorScheme;

          Future<void> write(NotificationPrefs next) async {
            prefs = next;
            await ref.read(notificationsProvider.notifier).update(next);
            setSheetState(() {});
          }

          Future<void> pick({required bool start}) async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: start ? prefs.quietStartHour : prefs.quietEndHour,
                minute: 0,
              ),
              helpText: start ? 'Quiet hours start' : 'Quiet hours end',
            );
            if (picked == null) return;
            await write(
              start
                  ? prefs.copyWith(quietStartHour: picked.hour)
                  : prefs.copyWith(quietEndHour: picked.hour),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              Gap.lg,
              Gap.lg,
              Gap.lg,
              Gap.lg + MediaQuery.paddingOf(context).bottom,
            ),
            child: GlassPanel(
              level: 2,
              blur: 20.0,
              radius: Radii.hero,
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  Text('Quiet hours', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: Gap.xs),
                  Text(
                    'Mute every reminder between these times.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  GlassRow(
                    title: 'Quiet hours',
                    subtitle: prefs.quietHoursEnabled
                        ? 'Muted ${_clock(context, prefs.quietStartHour)} – '
                              '${_clock(context, prefs.quietEndHour)}'
                        : 'Off',
                    trailing: GlassToggle(
                      value: prefs.quietHoursEnabled,
                      semanticLabel: 'Quiet hours',
                      onChanged: (v) =>
                          write(prefs.copyWith(quietHoursEnabled: v)),
                    ),
                  ),
                  GlassRow(
                    title: 'Starts',
                    icon: Icons.schedule_rounded,
                    trailing: _TimeValue(
                      value: _clock(context, prefs.quietStartHour),
                    ),
                    onTap: () => pick(start: true),
                  ),
                  GlassRow(
                    title: 'Ends',
                    icon: Icons.schedule_rounded,
                    trailing: _TimeValue(
                      value: _clock(context, prefs.quietEndHour),
                    ),
                    showDivider: false,
                    onTap: () => pick(start: false),
                  ),
                  const SizedBox(height: Gap.xl),
                  GlassActionButton(
                    label: 'Done',
                    icon: Icons.check_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return GlassRow(
      title: title,
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: GlassToggle(
        value: value,
        accent: accent,
        semanticLabel: title,
        onChanged: onChanged,
      ),
    );
  }
}

class _TimeValue extends StatelessWidget {
  const _TimeValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: Gap.xs),
        const GlassChevron(),
      ],
    );
  }
}

/// 24-hour clock so the window reads identically in every locale.
String _clock(BuildContext context, int hour) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: hour, minute: 0),
      alwaysUse24HourFormat: true,
    );

int _activeCount(NotificationPrefs p) => [
  p.sessionReminders,
  p.dailySummary,
  p.weeklyReport,
  p.streakAlerts,
  p.blockingAlerts,
  p.buddyUpdates,
  p.groupActivity,
  p.challengeInvites,
].where((on) => on).length;
