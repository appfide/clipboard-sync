import 'package:clipboard_sync/features/diagnostics/diagnostics_page.dart';
import 'package:clipboard_sync/features/history/history_page.dart';
import 'package:clipboard_sync/features/onboarding/onboarding_page.dart';
import 'package:clipboard_sync/features/settings/backend_setup_page.dart';
import 'package:clipboard_sync/features/settings/settings_page.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// App routes. Redirects to onboarding until a backend is chosen.
final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
  return GoRouter(
    initialLocation: onboarded ? '/' : '/onboarding',
    redirect: (context, state) {
      final inOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!onboarded && !inOnboarding) return '/onboarding';
      if (onboarded && inOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HistoryPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
        path: '/onboarding/backend',
        builder: (_, _) => const BackendSetupPage(onboarding: true),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/settings/backend',
        builder: (_, _) => const BackendSetupPage(),
      ),
      GoRoute(
        path: '/settings/diagnostics',
        builder: (_, _) => const DiagnosticsPage(),
      ),
    ],
  );
});
