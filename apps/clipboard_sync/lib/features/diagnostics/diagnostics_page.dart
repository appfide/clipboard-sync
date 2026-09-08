import 'package:clipboard_sync/core/build_info.dart';
import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Redacted log viewer for bug reports.
class DiagnosticsPage extends ConsumerWidget {
  /// Creates the page.
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final status = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);
    final c = context.colors;
    final header = [
      'Clipboard Sync ${BuildInfo.version} (${BuildInfo.gitSha})',
      'platform=${PlatformInfo.name} backend=${s.backendId} encrypted=${s.encryptionEnabled}',
      'device=${s.deviceId}',
      'status=$status',
    ].join('\n');
    const mono = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'monospace'],
      fontSize: 12,
      height: 1.5,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Copy logs'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: '$header\n\n${log.export()}'),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logs copied — secrets redacted'),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: ContentColumn(
        maxWidth: 900,
        child: ValueListenableBuilder<int>(
          valueListenable: log.revision,
          builder: (context, _, _) {
            final entries = log.entries.reversed.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      header,
                      style: mono.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Recent events (${entries.length})',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: entries.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No events yet.'),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < entries.length; i++) ...[
                              if (i > 0) const Divider(),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _LevelDot(entries[i].level.name),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SelectableText(
                                            entries[i].message,
                                            style: mono.copyWith(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            entries[i].time.toIso8601String(),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: c.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot(this.level);
  final String level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final color = switch (level) {
      'error' => scheme.error,
      'warning' => c.warning,
      'info' => scheme.primary,
      _ => c.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
