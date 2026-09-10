import 'package:clipboard_sync/app/app_shell.dart';
import 'package:clipboard_sync/features/about/about_page.dart';
import 'package:clipboard_sync/features/devices/devices_page.dart';
import 'package:clipboard_sync/features/devices/join_page.dart';
import 'package:clipboard_sync/features/devices/pair_page.dart';
import 'package:clipboard_sync/features/diagnostics/diagnostics_page.dart';
import 'package:clipboard_sync/features/history/history_page.dart';
import 'package:clipboard_sync/features/onboarding/onboarding_page.dart';
import 'package:clipboard_sync/features/settings/backend_setup_page.dart';
import 'package:clipboard_sync/features/settings/settings_page.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// App routes. Redirects to onboarding until a backend is chosen.
final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
  return buildAppRouter(onboarded: onboarded);
});

/// Builds the router; exposed so screenshot/golden tests can start at any
/// [initialLocation].
GoRouter buildAppRouter({required bool onboarded, String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? (onboarded ? '/' : '/onboarding'),
    redirect: (context, state) {
      final inOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!onboarded && !inOnboarding) return '/onboarding';
      if (onboarded && inOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
        path: '/onboarding/backend',
        builder: (_, _) => const BackendSetupPage(onboarding: true),
      ),
      GoRoute(
        path: '/onboarding/join',
        builder: (_, _) => const JoinPage(onboarding: true),
      ),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, s) => _fade(s, const HistoryPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, s) => _fade(s, const SettingsPage()),
            routes: [
              GoRoute(
                path: 'backend',
                builder: (_, _) => const BackendSetupPage(),
              ),
              GoRoute(
                path: 'diagnostics',
                builder: (_, _) => const DiagnosticsPage(),
              ),
              GoRoute(
                path: 'devices',
                builder: (_, _) => const DevicesPage(),
                routes: [
                  GoRoute(
                    path: 'pair',
                    builder: (_, _) => const PairPage(),
                  ),
                  GoRoute(
                    path: 'join',
                    builder: (_, _) => const JoinPage(),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/about',
            pageBuilder: (_, s) => _fade(s, const AboutPage()),
          ),
        ],
      ),
    ],
  );
}

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    );
