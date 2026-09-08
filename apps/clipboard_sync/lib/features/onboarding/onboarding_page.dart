import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/brand_mark.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// First-run welcome.
class OnboardingPage extends StatelessWidget {
  /// Creates the page.
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.18),
                      scheme.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ContentColumn(
              maxWidth: 520,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 64),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your clipboard,\neverywhere you work.',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Clipboard Sync keeps history across macOS, Windows, Linux, Android and iOS — '
                      'synced through a database you own. No accounts, no middleman.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _Point(
                      Icons.storage_rounded,
                      'Bring your own database',
                      'Supabase, PocketBase, CouchDB, Firestore or MongoDB.',
                    ),
                    const _Point(
                      Icons.lock_rounded,
                      'End-to-end encryption',
                      'Optional. The database only ever sees ciphertext.',
                    ),
                    const _Point(
                      Icons.code_rounded,
                      'Open source',
                      'MIT licensed — github.com/appfide/clipboard-sync',
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      key: const ValueKey('onboarding-next'),
                      onPressed: () => context.go('/onboarding/backend'),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('Choose a database'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LeadingIcon(icon: icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
