import 'dart:async';

import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/brand_mark.dart';
import 'package:clipboard_sync/ui/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Adaptive navigation chrome: a rail with brand + status on desktop widths,
/// a bottom navigation bar on phones.
class AppShell extends ConsumerWidget {
  /// Creates the shell around [child].
  const AppShell({required this.child, super.key});

  /// Routed page.
  final Widget child;

  static const List<
    ({IconData icon, String label, String path, IconData selected})
  >
  _destinations = [
    (
      path: '/',
      icon: Icons.history_rounded,
      selected: Icons.history_rounded,
      label: 'History',
    ),
    (
      path: '/settings',
      icon: Icons.tune_rounded,
      selected: Icons.tune_rounded,
      label: 'Settings',
    ),
    (
      path: '/about',
      icon: Icons.info_outline_rounded,
      selected: Icons.info_rounded,
      label: 'About',
    ),
  ];

  int _indexOf(String location) {
    if (location.startsWith('/settings')) return 1;
    if (location.startsWith('/about')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<RevocationNotice?>(revocationProvider, (prev, next) {
      if (next == null) return;
      unawaited(_showRevoked(context, ref, next));
    });
    final location = GoRouterState.of(context).uri.path;
    final index = _indexOf(location);
    final wide =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;

    if (!wide) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => context.go(_destinations[i].path),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 96,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: context.colors.border)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const BrandMark(),
                const SizedBox(height: 16),
                Expanded(
                  child: NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: (i) =>
                        context.go(_destinations[i].path),
                    minWidth: 96,
                    groupAlignment: -1,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Tooltip(
                    message: status.lastError ?? 'Sync status',
                    child: StatusPill(
                      status: status,
                      pending: pending,
                      compact: true,
                      onTap: () => context.go(
                        status.phase.name == 'error'
                            ? '/settings/backend'
                            : '/settings',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Future<void> _showRevoked(
  BuildContext context,
  WidgetRef ref,
  RevocationNotice notice,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('revoked-dialog'),
      icon: Icon(
        Icons.person_off_rounded,
        color: Theme.of(ctx).colorScheme.error,
      ),
      title: Text(notice.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Text(notice.detail),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  ref.read(revocationProvider.notifier).notice = null;
}
