import 'dart:async';

import 'package:clipboard_sync/features/devices/device_widgets.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/empty_state.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Every device in the sync group with block / role / expiry / remove
/// actions, plus entry points to add or join.
class DevicesPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final controller = ref.read(syncControllerProvider.notifier);
    if (!controller.canManageDevices) return;
    setState(() => _busy = true);
    try {
      await controller.refreshDevices();
    } catch (e) {
      _toast('Could not load devices: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() op, String done) async {
    setState(() => _busy = true);
    try {
      await op();
      _toast(done);
    } on BackendException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAction(Device d, String action) async {
    final controller = ref.read(syncControllerProvider.notifier);
    switch (action) {
      case 'block':
        final ok = await confirm(
          context,
          title: 'Block ${d.name}?',
          message:
              'Other devices will ignore its clips and it will stop syncing the next time it checks in (about a minute). You can unblock it later.',
          action: 'Block',
          destructive: true,
        );
        if (ok) {
          await _run(() => controller.blockDevice(d.id), 'Blocked ${d.name}');
        }
      case 'unblock':
        await _run(() => controller.unblockDevice(d.id), 'Unblocked ${d.name}');
      case 'role':
        final role = await pickRole(context, d.role);
        if (role != null && role != d.role) {
          await _run(
            () => controller.setDeviceRole(d.id, role),
            '${d.name}: ${role.label}',
          );
        }
      case 'expiry':
        final picked = await pickAccessDuration(context);
        if (picked == null) return;
        final dur = picked.$1;
        await _run(
          () => controller.setDeviceExpiry(
            d.id,
            dur == null ? null : DateTime.now().toUtc().add(dur),
          ),
          dur == null
              ? '${d.name}: no expiry'
              : '${d.name}: access ends in ${accessDurations[dur]!.toLowerCase()}',
        );
      case 'remove':
        final ok = await confirm(
          context,
          title: 'Remove ${d.name}?',
          message:
              'The device will delete its copy of the database credentials the next time it checks in. Its clips stay in the history. Use Forget afterwards to delete the entry.',
          action: 'Remove',
          destructive: true,
        );
        if (ok) {
          await _run(() => controller.removeDevice(d.id), 'Removed ${d.name}');
        }
      case 'forget':
        final ok =
            d.isPending ||
            await confirm(
              context,
              title: 'Forget ${d.name}?',
              message:
                  'Deletes the entry. If the device is still running it will notice on its next check-in and disconnect.',
              action: 'Forget',
              destructive: true,
            );
        if (ok) {
          await _run(() => controller.forgetDevice(d.id), 'Forgot ${d.name}');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final devices = ref.watch(deviceListProvider).value ?? const <Device>[];
    final status = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);
    final c = context.colors;
    final connected = s.syncsRemotely && status.phase != SyncPhase.stopped;

    final sorted = [...devices]
      ..sort((a, b) {
        int rank(Device d) => d.id == s.deviceId
            ? 0
            : switch (d.status) {
                DeviceStatus.active => d.isPending ? 2 : 1,
                DeviceStatus.blocked => 3,
                DeviceStatus.removed => 4,
              };
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : b.lastSeen.compareTo(a.lastSeen);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy || !connected ? null : _refresh,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !s.syncsRemotely
          ? EmptyState(
              icon: Icons.devices_rounded,
              title: 'No sync group yet',
              message:
                  'Connect a database, or join a group from a device that already has one.',
              action: Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/settings/backend'),
                    icon: const Icon(Icons.storage_rounded, size: 18),
                    label: const Text('Choose a database'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/settings/devices/join'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Join with a code'),
                  ),
                ],
              ),
            )
          : ContentColumn(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('add-device'),
                          onPressed: connected
                              ? () => context.push('/settings/devices/pair')
                              : null,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                          label: const Text('Add a device'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/settings/devices/join'),
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: const Text('Join another group'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!connected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          status.lastError ??
                              'Not connected — device management needs a working connection.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    SectionCard(
                      title: 'In this group',
                      subtitle: sorted.isEmpty
                          ? null
                          : '${sorted.length} device${sorted.length == 1 ? '' : 's'}',
                      children: sorted.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _busy ? 'Loading…' : 'No devices found.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ]
                          : [
                              for (final d in sorted)
                                DeviceTile(
                                  device: d,
                                  isSelf: d.id == s.deviceId,
                                  onAction: d.id == s.deviceId || !connected
                                      ? null
                                      : (a) => _onAction(d, a),
                                ),
                            ],
                    ),
                    const EnforcementNote(),
                    const SizedBox(height: 12),
                    Text(
                      'Rename this device under Settings → Devices → This device.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
