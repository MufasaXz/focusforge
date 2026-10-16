import '../../core/localization/app_strings.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/social_providers.dart';
import '../../shared/widgets/app_page.dart';
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
    final prefs = ref.watch(notificationsProvider);

    return AppPage(
      title: context.tr("Notifications"),
      subtitle: context.tr("{0} of 8 reminders on", [_activeCount(prefs)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: context.tr("Your running timer"),
            footnote: context.tr(
              "Dynamic bars are provided by your device software. Availability and appearance vary by device.",
            ),
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(context.tr("Countdown & dynamic bars")),
                subtitle: Text(
                  context.tr(
                    "Keep your subject and countdown in an ongoing notification. Allow notifications in App access.",
                  ),
                ),
                trailing: const AppChevron(),
                onTap: () => context.goNamed(AppRoutes.permissions),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Focus reminders"),
            children: [
              _SwitchRow(
                title: context.tr("Session reminders"),
                subtitle: context.tr("“Time to study Physics!”"),
                value: prefs.sessionReminders,
                onChanged: (v) =>
                    _save(ref, prefs.copyWith(sessionReminders: v)),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Progress"),
            children: [
              _SwitchRow(
                title: context.tr("Daily summary"),
                subtitle: context.tr("Your focus total at the end of the day"),
                value: prefs.dailySummary,
                onChanged: (v) => _save(ref, prefs.copyWith(dailySummary: v)),
              ),
              _SwitchRow(
                title: context.tr("Weekly report"),
                subtitle: context.tr("A Sunday recap of the week"),
                value: prefs.weeklyReport,
                onChanged: (v) => _save(ref, prefs.copyWith(weeklyReport: v)),
              ),
              _SwitchRow(
                title: context.tr("Streak risk alerts"),
                subtitle: context.tr("A nudge before a streak breaks"),
                value: prefs.streakAlerts,
                onChanged: (v) => _save(ref, prefs.copyWith(streakAlerts: v)),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Blocking"),
            footnote: context.tr(
              "These fire while a block is active, so they can be frequent.",
            ),
            children: [
              _SwitchRow(
                title: context.tr("Real-time block alerts"),
                subtitle: context.tr("“Instagram Reels blocked”"),
                value: prefs.blockingAlerts,
                onChanged: (v) => _save(ref, prefs.copyWith(blockingAlerts: v)),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Social"),
            children: [
              _SwitchRow(
                title: context.tr("Study buddy updates"),
                subtitle: context.tr(
                  "When a buddy starts or finishes a session",
                ),
                value: prefs.buddyUpdates,
                onChanged: (v) => _save(ref, prefs.copyWith(buddyUpdates: v)),
              ),
              _SwitchRow(
                title: context.tr("Group activity"),
                subtitle: context.tr("Targets met and new members"),
                value: prefs.groupActivity,
                onChanged: (v) => _save(ref, prefs.copyWith(groupActivity: v)),
              ),
              _SwitchRow(
                title: context.tr("Challenge invitations"),
                subtitle: context.tr("Weekly challenges from friends"),
                value: prefs.challengeInvites,
                onChanged: (v) =>
                    _save(ref, prefs.copyWith(challengeInvites: v)),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Quiet hours"),
            footnote: context.tr(
              "Reminders pause during the window; focus timers do not.",
            ),
            children: [
              ListTile(
                title: Text(context.tr("Quiet hours")),
                subtitle: Text(
                  prefs.quietHoursEnabled
                      ? context.tr("Muted {0} – {1}", [
                          _clock(context, prefs.quietStartHour),
                          _clock(context, prefs.quietEndHour),
                        ])
                      : context.tr("Off — notifications arrive at any hour"),
                ),
                leading: const Icon(Icons.bedtime_outlined),
                trailing: const AppChevron(),
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
              helpText: start
                  ? context.tr("Quiet hours start")
                  : context.tr("Quiet hours end"),
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
            // A modal sheet is one of the few surfaces the design lets blur —
            // σ24 over the low tonal surface, so the page stays legible behind.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.hero),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(Radii.hero),
                  ),
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
                      Text(
                        context.tr("Quiet hours"),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        context.tr("Mute every reminder between these times."),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: Gap.lg),
                      _SwitchRow(
                        title: context.tr("Quiet hours"),
                        subtitle: prefs.quietHoursEnabled
                            ? context.tr("Muted {0} – {1}", [
                                _clock(context, prefs.quietStartHour),
                                _clock(context, prefs.quietEndHour),
                              ])
                            : context.tr("Off"),
                        value: prefs.quietHoursEnabled,
                        onChanged: (v) =>
                            write(prefs.copyWith(quietHoursEnabled: v)),
                      ),
                      ListTile(
                        title: Text(context.tr("Starts")),
                        leading: const Icon(Icons.schedule_outlined),
                        trailing: _TimeValue(
                          value: _clock(context, prefs.quietStartHour),
                        ),
                        onTap: () => pick(start: true),
                      ),
                      ListTile(
                        title: Text(context.tr("Ends")),
                        leading: const Icon(Icons.schedule_outlined),
                        trailing: _TimeValue(
                          value: _clock(context, prefs.quietEndHour),
                        ),
                        onTap: () => pick(start: false),
                      ),
                      const SizedBox(height: Gap.xl),
                      AppActionButton(
                        label: context.tr("Done"),
                        icon: Icons.check_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
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
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Semantics(
        label: title,
        child: Switch.adaptive(
          value: value,
          onChanged: (next) {
            // A flip is a commitment — the tap that made it should be felt,
            // not just seen.
            HapticFeedback.lightImpact();
            onChanged(next);
          },
        ),
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
        const AppChevron(),
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
