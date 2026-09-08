import 'dart:convert';

import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/local/local_store.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Main screen: searchable clipboard history + sync status.
class HistoryPage extends ConsumerWidget {
  /// Creates the page.
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final status = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard Sync'),
        actions: [
          IconButton(
            tooltip: PlatformInfo.isMobile
                ? 'Capture clipboard & sync'
                : 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await controller.captureNow();
              await controller.syncNow();
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: const ValueKey('search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search history',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (q) =>
                  ref.read(historyQueryProvider.notifier).query = q,
            ),
          ),
        ),
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load history: $e')),
        data: (rows) => rows.isEmpty
            ? const _Empty()
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ClipTile(rows[i]),
              ),
      ),
      bottomNavigationBar: _StatusBar(status),
      floatingActionButton: PlatformInfo.isMobile
          ? FloatingActionButton.extended(
              onPressed: () async {
                await controller.captureNow();
                await controller.syncNow();
              },
              icon: const Icon(Icons.content_paste),
              label: const Text('Capture clipboard'),
            )
          : null,
    );
  }
}

class _ClipTile extends ConsumerWidget {
  const _ClipTile(this.entry);
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = entry.item;
    final controller = ref.read(syncControllerProvider.notifier);
    final store = ref.read(localStoreProvider);
    final leading = _leadingFor(item);
    final preview = item.type.isBinary
        ? '${item.type.wire} · ${(item.sizeBytes / 1024).toStringAsFixed(0)} KB'
        : item.content.replaceAll('\n', ' ⏎ ');
    return ListTile(
      key: ValueKey('clip-${item.id}'),
      leading: leading,
      title: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.deviceName} · ${_ago(item.createdAt)}${entry.synced ? '' : ' · pending'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.pinned) const Icon(Icons.push_pin, size: 16),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'copy':
                  await controller.copyToClipboard(item);
                case 'pin':
                  await store.setPinned(item.id, pinned: !entry.pinned);
                case 'delete':
                  await controller.delete(item.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy')),
              PopupMenuItem(
                value: 'pin',
                child: Text(entry.pinned ? 'Unpin' : 'Pin'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete everywhere'),
              ),
            ],
          ),
        ],
      ),
      onTap: () async {
        await controller.copyToClipboard(item);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
    );
  }

  static Widget _leadingFor(ClipItem item) {
    if (item.type == ClipContentType.image) {
      return SizedBox.square(
        dimension: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            base64Decode(item.content),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    final icon = switch (item.type) {
      ClipContentType.url => Icons.link,
      ClipContentType.html => Icons.code,
      ClipContentType.file => Icons.insert_drive_file_outlined,
      ClipContentType.image || ClipContentType.text => Icons.notes,
    };
    return Icon(icon);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return DateFormat.yMMMd().format(t.toLocal());
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar(this.status);
  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final (icon, color, text) = switch (status.phase) {
      SyncPhase.stopped => (Icons.cloud_off, scheme.outline, 'Local only'),
      SyncPhase.idle => (
        Icons.cloud_done,
        scheme.primary,
        status.realtime ? 'Live' : 'Synced',
      ),
      SyncPhase.syncing => (Icons.cloud_sync, scheme.primary, 'Syncing…'),
      SyncPhase.error => (
        Icons.cloud_off,
        scheme.error,
        status.lastError ?? 'Error',
      ),
    };
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: status.phase == SyncPhase.error
              ? () => context.push('/settings/backend')
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color),
                  ),
                ),
                if (pending > 0)
                  Text(
                    '$pending pending',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (status.lastSyncAt != null && pending == 0)
                  Text(
                    DateFormat.Hm().format(status.lastSyncAt!.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.content_paste_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            PlatformInfo.isDesktop
                ? 'Copy something — it will show up here and sync to your other devices.'
                : 'Copy something, then open the app or tap Capture.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
