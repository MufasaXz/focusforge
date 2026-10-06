import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/app_providers.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/focus/focus_screen.dart';
import '../features/onboarding/auth_screen.dart';
import '../features/onboarding/onboarding_flow.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/achievements_screen.dart';
import '../features/settings/leaderboard_screen.dart';
import '../features/settings/notifications_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/strict_mode_screen.dart';
import '../features/settings/study_groups_screen.dart';
import '../features/shield/breath_gate.dart';
import '../features/shield/shield_screen.dart';
import 'shell/app_shell.dart';

/// Route names in one place. `context.goNamed(AppRoutes.focus)` beats a string
/// literal that a rename can silently break.
class AppRoutes {
  const AppRoutes._();

  static const dashboard = 'dashboard';
  static const shield = 'shield';
  static const focus = 'focus';
  static const profile = 'profile';

  static const onboarding = 'onboarding';
  static const auth = 'auth';
  static const breathGate = 'breath-gate';

  static const groups = 'groups';
  static const achievements = 'achievements';
  static const leaderboard = 'leaderboard';
  static const strictMode = 'strict-mode';
  static const notifications = 'notifications';
  static const privacy = 'privacy';
  static const about = 'about';

  static const paths = <String, String>{
    dashboard: '/dashboard',
    shield: '/shield',
    focus: '/focus',
    profile: '/profile',
    onboarding: '/onboarding',
    auth: '/auth',
    breathGate: '/breath-gate',
    groups: '/profile/groups',
    achievements: '/profile/achievements',
    leaderboard: '/profile/leaderboard',
    strictMode: '/profile/strict-mode',
    notifications: '/profile/notifications',
    privacy: '/profile/privacy',
    about: '/profile/about',
  };
}

/// The app's navigation graph.
///
/// Two structural decisions worth knowing:
///
///  * The four tabs live in a [StatefulShellRoute.indexedStack]. Each branch
///    owns its own [Navigator], so pushing "Achievements" from Profile keeps
///    the tab bar visible and preserves the scroll position of the other three
///    tabs. A single flat Navigator would lose all of that.
///  * Onboarding and the auth screen sit *outside* the shell. They are the one
///    place where the app should feel like a different, distraction-free
///    surface — no nav bar competing for attention.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.paths[AppRoutes.dashboard]!,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final onboarded = ref.read(userProvider).onboardingComplete;
      final location = state.matchedLocation;
      final inOnboarding = location.startsWith('/onboarding') ||
          location == AppRoutes.paths[AppRoutes.auth];

      if (!onboarded && !inOnboarding) {
        return AppRoutes.paths[AppRoutes.onboarding];
      }
      if (onboarded && inOnboarding) {
        return AppRoutes.paths[AppRoutes.dashboard];
      }
      return null;
    },
    routes: [
      // -- Onboarding (outside the shell) ------------------------------------
      GoRoute(
        path: '/onboarding',
        name: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingFlow(),
      ),
      GoRoute(
        path: '/auth',
        name: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),

      // -- Deep Breath Gate (full-bleed, deliberately modal) -----------------
      GoRoute(
        path: '/breath-gate',
        name: AppRoutes.breathGate,
        builder: (context, state) {
          final args = state.extra;
          return BreathGateScreen(
            // The gate is also reachable from the Shield screen's preview, and
            // a deep link carries nothing at all. Both fall back to a plain
            // name with no package behind it.
            args: args is BreathGateArgs
                ? args
                : const BreathGateArgs(appName: 'That app'),
          );
        },
      ),

      // -- The four tabs -----------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                name: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shield',
                name: AppRoutes.shield,
                builder: (context, state) => const ShieldScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/focus',
                name: AppRoutes.focus,
                builder: (context, state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'groups',
                    name: AppRoutes.groups,
                    builder: (context, state) => const StudyGroupsScreen(),
                  ),
                  GoRoute(
                    path: 'achievements',
                    name: AppRoutes.achievements,
                    builder: (context, state) => const AchievementsScreen(),
                  ),
                  GoRoute(
                    path: 'leaderboard',
                    name: AppRoutes.leaderboard,
                    builder: (context, state) => const LeaderboardScreen(),
                  ),
                  GoRoute(
                    path: 'strict-mode',
                    name: AppRoutes.strictMode,
                    builder: (context, state) => const StrictModeScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    name: AppRoutes.notifications,
                    builder: (context, state) => const NotificationsScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    name: AppRoutes.privacy,
                    builder: (context, state) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    name: AppRoutes.about,
                    builder: (context, state) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteError(state.error),
  );
});

/// A missing route should never show a red screen in a shipped build.
class _RouteError extends StatelessWidget {
  const _RouteError(this.error);

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 40),
              const SizedBox(height: 16),
              const Text('That screen moved.'),
              const SizedBox(height: 8),
              Text(
                '${error ?? 'Unknown route'}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    context.go(AppRoutes.paths[AppRoutes.dashboard]!),
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
