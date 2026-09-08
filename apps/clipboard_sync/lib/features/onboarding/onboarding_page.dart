import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// First-run welcome.
class OnboardingPage extends StatelessWidget {
  /// Creates the page.
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.content_paste,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Clipboard Sync',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your clipboard history, synced through a database you own. '
                'No accounts, no middleman — bring Supabase, PocketBase, CouchDB, Firestore or MongoDB.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const _Point(
                Icons.lock_outline,
                'Optional end-to-end encryption keeps the database blind.',
              ),
              const _Point(
                Icons.devices,
                'Works on macOS, Windows, Linux, Android and iOS.',
              ),
              const _Point(
                Icons.code,
                'Open source (MIT) — github.com/appfide/clipboard-sync',
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('onboarding-next'),
                onPressed: () => context.go('/onboarding/backend'),
                child: const Text('Choose a database'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
