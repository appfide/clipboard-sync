import 'package:clipboard_sync/core/build_info.dart';
import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
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
    final header = [
      'Clipboard Sync ${BuildInfo.version} (${BuildInfo.gitSha})',
      'platform=${PlatformInfo.name} backend=${s.backendId} encrypted=${s.encryptionEnabled}',
      'device=${s.deviceId} status=$status',
      '',
    ].join('\n');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy redacted logs',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: '$header${log.export()}'),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logs copied (secrets redacted)'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: log.revision,
        builder: (context, _, _) {
          final entries = log.entries.reversed.toList();
          return ListView.builder(
            itemCount: entries.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    header,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                );
              }
              final e = entries[i - 1];
              return ListTile(
                dense: true,
                title: Text(
                  e.message,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                subtitle: Text('${e.time.toIso8601String()} ${e.level.name}'),
              );
            },
          );
        },
      ),
    );
  }
}
