import 'dart:convert';

import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/local/local_store.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/empty_state.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipboard_sync/ui/widgets/status_pill.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Main screen: searchable clipboard history grouped by day.
class HistoryPage extends ConsumerWidget {
  /// Creates the page.
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final controller = ref.read(syncControllerProvider.notifier);
    final wide =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;
    final theme = Theme.of(context);

    Future<void> syncNow() async {
      await controller.captureNow();
      await controller.syncNow();
    }

    return Scaffold(
      body: SafeArea(
        child: ContentColumn(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History', style: theme.textTheme.headlineSmall),
                          Text(
                            history.value == null
                                ? ' '
                                : '${history.value!.length} item${history.value!.length == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: StatusPill(
                          status: status,
                          pending: pending,
                          onTap: () => context.go('/settings/backend'),
                        ),
                      ),
                    IconButton(
                      tooltip: PlatformInfo.isMobile
                          ? 'Capture clipboard & sync'
                          : 'Sync now',
                      icon: const Icon(Icons.sync_rounded),
                      onPressed: syncNow,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextField(
                  key: const ValueKey('search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search history',
                    isDense: true,
                  ),
                  onChanged: (q) =>
                      ref.read(historyQueryProvider.notifier).query = q,
                ),
              ),
              Expanded(
                child: history.when(
                  loading: () => const _Skeleton(),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load history',
                    message: '$e',
                  ),
                  data: (rows) => rows.isEmpty
                      ? EmptyState(
                          icon: Icons.content_paste_search_rounded,
                          title: 'Nothing here yet',
                          message: PlatformInfo.isDesktop
                              ? 'Copy anything — it shows up here and syncs to your other devices.'
                              : 'Copy something, then open the app or tap Capture.',
                          action: PlatformInfo.isMobile
                              ? FilledButton.icon(
                                  onPressed: syncNow,
                                  icon: const Icon(Icons.content_paste_rounded),
                                  label: const Text('Capture clipboard'),
                                )
                              : null,
                        )
                      : _GroupedList(rows),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: PlatformInfo.isMobile
          ? FloatingActionButton.extended(
              onPressed: syncNow,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Capture'),
            )
          : null,
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList(this.rows);
  final List<HistoryEntry> rows;

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    String? last;
    for (final r in rows) {
      final label = r.pinned ? 'Pinned' : _dayLabel(r.item.createdAt);
      if (label != last) {
        items.add(label);
        last = label;
      }
      items.add(r);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        if (it is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              it.toUpperCase(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: context.colors.muted),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ClipCard(it as HistoryEntry),
        );
      },
    );
  }

  static String _dayLabel(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final d = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(local);
    return DateFormat.yMMMd().format(local);
  }
}

class _ClipCard extends ConsumerStatefulWidget {
  const _ClipCard(this.entry);
  final HistoryEntry entry;

  @override
  ConsumerState<_ClipCard> createState() => _ClipCardState();
}

class _ClipCardState extends ConsumerState<_ClipCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final item = entry.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final controller = ref.read(syncControllerProvider.notifier);
    final store = ref.read(localStoreProvider);

    Future<void> copy() async {
      await controller.copyToClipboard(item);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
      }
    }

    final preview = item.type.isBinary
        ? '${item.type.wire} · ${(item.sizeBytes / 1024).toStringAsFixed(0)} KB'
        : item.content.trim().replaceAll(RegExp(r'\s+'), ' ');

    final card = Card(
      key: ValueKey('clip-${item.id}'),
      color: _hover ? scheme.surfaceContainer : c.surfaceRaised,
      child: InkWell(
        onTap: copy,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeBadge(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: item.type == ClipContentType.url
                          ? theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            )
                          : theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _platformIcon(item.deviceName),
                          size: 14,
                          color: c.muted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.deviceName,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '  ·  ${_ago(item.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (!entry.synced) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 14,
                            color: c.warning,
                          ),
                        ],
                        if (item.encrypted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: c.muted,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              AnimatedOpacity(
                duration: AppTokens.fast,
                opacity: _hover || PlatformInfo.isMobile ? 1 : 0.55,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.pinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (v) async {
                        switch (v) {
                          case 'copy':
                            await copy();
                          case 'pin':
                            await store.setPinned(
                              item.id,
                              pinned: !entry.pinned,
                            );
                          case 'delete':
                            await controller.delete(item.id);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: _MenuRow(Icons.copy_rounded, 'Copy'),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: _MenuRow(
                            entry.pinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin_rounded,
                            entry.pinned ? 'Unpin' : 'Pin',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: _MenuRow(
                            Icons.delete_outline_rounded,
                            'Delete everywhere',
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PlatformInfo.isMobile
          ? Dismissible(
              key: ValueKey('dismiss-${item.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => controller.delete(item.id),
              child: card,
            )
          : card,
    );
  }

  static IconData _platformIcon(String deviceName) {
    final n = deviceName.toLowerCase();
    if (n.contains('iphone') || n.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (n.contains('android')) return Icons.phone_android_rounded;
    if (n.contains('mac')) return Icons.laptop_mac_rounded;
    return Icons.computer_rounded;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return DateFormat.jm().format(t.toLocal());
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.item);
  final ClipItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (item.type == ClipContentType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          base64Decode(item.content),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final (icon, color) = switch (item.type) {
      ClipContentType.url => (Icons.link_rounded, scheme.primary),
      ClipContentType.html => (Icons.code_rounded, AppTokens.amber600),
      ClipContentType.file => (
        Icons.insert_drive_file_outlined,
        scheme.secondary,
      ),
      ClipContentType.image ||
      ClipContentType.text => (Icons.notes_rounded, scheme.secondary),
    };
    return LeadingIcon(icon: icon, color: color, size: 40);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color ?? context.colors.muted),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: color)),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                bar(40, 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(double.infinity, 14),
                      const SizedBox(height: 8),
                      bar(140, 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
