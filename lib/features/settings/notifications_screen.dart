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
import '../assistant/nudges/pip_nudges.dart';
import '../../shared/widgets/app_page.dart';
import 'settings_support.dart';

/// Notification preferences: the reminders FocusForge sends, which are Pip's,
/// and quiet hours over them.
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
      subtitle: context.tr("{0} of {1} enabled", [_activeCount(prefs), 2]),
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
                    _save(context, ref, prefs.copyWith(sessionReminders: v)),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Progress"),
            children: [
              _SwitchRow(
                title: context.tr("Streak risk alerts"),
                subtitle: context.tr("A nudge before a streak breaks"),
                value: prefs.streakAlerts,
                onChanged: (v) =>
                    _save(context, ref, prefs.copyWith(streakAlerts: v)),
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
                subtitle: Text(_quietSummary(context, prefs)),
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

  /// Saves [next] and sets Pip's reminders again under it.
  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    NotificationPrefs next,
  ) async {
    final strings = AppStrings.of(context);
    await ref.read(notificationsProvider.notifier).update(next);
    await PipNudges.sync(ref.read, strings);
  }

  Future<void> _editQuietHours(BuildContext context, WidgetRef ref) async {
    var prefs = ref.read(notificationsProvider);
    // The change that could not be saved, kept so Retry can save it again.
    NotificationPrefs? unsaved;
    final strings = AppStrings.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final cs = Theme.of(context).colorScheme;

          Future<void> write(NotificationPrefs next) async {
            prefs = next;
            unsaved = null;
            setSheetState(() {});
            try {
              await ref.read(notificationsProvider.notifier).update(next);
            } catch (_) {
              unsaved = next;
            }
            if (context.mounted) setSheetState(() {});
          }

          Future<void> pick({required bool start}) async {
            final current = start ? prefs.quietStart : prefs.quietEnd;
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
              helpText: start
                  ? context.tr("Quiet hours start")
                  : context.tr("Quiet hours end"),
            );
            if (picked == null) return;
            final minute = picked.hour * 60 + picked.minute;
            await write(
              start
                  ? prefs.copyWith(quietStart: minute)
                  : prefs.copyWith(quietEnd: minute),
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
                  // The rows' ripples need a Material above this colour,
                  // or a tap on Starts or Ends shows nothing.
                  child: Material(
                    type: MaterialType.transparency,
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
                          context.tr(
                            "Mute every reminder between these times.",
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: Gap.lg),
                        _SwitchRow(
                          title: context.tr("Quiet hours"),
                          subtitle: prefs.quietHoursEnabled
                              ? _quietSummary(context, prefs)
                              : context.tr("Off"),
                          value: prefs.quietHoursEnabled,
                          onChanged: (v) =>
                              write(prefs.copyWith(quietHoursEnabled: v)),
                        ),
                        ListTile(
                          title: Text(context.tr("Starts")),
                          leading: const Icon(Icons.schedule_outlined),
                          trailing: _TimeValue(
                            value: _clock(context, prefs.quietStart),
                          ),
                          onTap: () => pick(start: true),
                        ),
                        ListTile(
                          title: Text(context.tr("Ends")),
                          leading: const Icon(Icons.schedule_outlined),
                          trailing: _TimeValue(
                            value: _clock(context, prefs.quietEnd),
                          ),
                          onTap: () => pick(start: false),
                        ),
                        // What the window does, in the terms it was set in.
                        if (prefs.quietWindow)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.lg,
                            ),
                            child: Text(
                              context.tr(
                                "Reminders due in this window wait until {0}. Calls for timetable blocks inside it are skipped.",
                                [_clock(context, prefs.quietEnd)],
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        if (unsaved case final failed?) ...[
                          const SizedBox(height: Gap.md),
                          Semantics(
                            liveRegion: true,
                            child: Row(
                              children: [
                                const SizedBox(width: Gap.lg),
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: cs.error,
                                ),
                                const SizedBox(width: Gap.sm),
                                Expanded(
                                  child: Text(
                                    context.tr(
                                      "Could not save quiet hours. Try again.",
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: cs.error),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => write(failed),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: Text(context.tr("Retry")),
                                ),
                              ],
                            ),
                          ),
                        ],
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
            ),
          );
        },
      ),
    );
    // Reminders set inside the new quiet hours wait until they end.
    await PipNudges.sync(ref.read, strings);
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
/// [minuteOfDay] as a 24-hour time, like 22:45.
String _clock(BuildContext context, int minuteOfDay) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      alwaysUse24HourFormat: true,
    );

/// One line for the whole window: off, empty, or the times it covers.
String _quietSummary(BuildContext context, NotificationPrefs prefs) {
  if (!prefs.quietHoursEnabled) {
    return context.tr("Off — notifications arrive at any hour");
  }
  if (!prefs.quietWindow) {
    return context.tr("Start and end are the same, so nothing is muted.");
  }
  return context.tr("Muted {0} – {1}", [
    _clock(context, prefs.quietStart),
    _clock(context, prefs.quietEnd),
  ]);
}

int _activeCount(NotificationPrefs p) =>
    [p.sessionReminders, p.streakAlerts].where((on) => on).length;
