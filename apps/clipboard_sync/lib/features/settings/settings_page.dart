import 'dart:async';

import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/features/settings/permissions_section.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// All preferences, grouped in cards.
class SettingsPage extends ConsumerWidget {
  /// Creates the page.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final descriptor = ref
        .watch(backendRegistryProvider)
        .descriptor(s.backendId);
    final shell = ref.watch(desktopShellProvider);
    final status = ref.watch(syncControllerProvider);
    final devices = ref.watch(deviceListProvider).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ContentColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text('Settings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: ref.watch(secretStoreProvider).degraded,
                builder: (context, degraded, _) => degraded
                    ? const _DegradedBanner()
                    : const SizedBox.shrink(),
              ),
              SectionCard(
                title: 'Sync',
                children: [
                  SettingRow(
                    icon: Icons.storage_rounded,
                    title: 'Database',
                    subtitle: descriptor?.displayName ?? s.backendId,
                    onTap: () => context.push('/settings/backend'),
                  ),
                  SettingRow(
                    icon: Icons.timer_outlined,
                    title: 'Poll interval',
                    subtitle: (descriptor?.supportsRealtime ?? false)
                        ? 'Realtime backend — used only as fallback'
                        : 'How often to check for changes',
                    trailing: _Dropdown<int>(
                      value: s.pollIntervalSeconds,
                      items: const {
                        2: '2 s',
                        5: '5 s',
                        10: '10 s',
                        30: '30 s',
                        60: '1 min',
                        300: '5 min',
                      },
                      onChanged: (v) => notifier.update(
                        (x) => x.copyWith(pollIntervalSeconds: v),
                      ),
                    ),
                  ),
                  SettingRow(
                    icon: Icons.auto_delete_outlined,
                    title: 'Keep history for',
                    subtitle: 'Older items are removed locally and remotely',
                    trailing: _Dropdown<int>(
                      value: s.retentionDays,
                      items: const {
                        1: '1 day',
                        7: '7 days',
                        30: '30 days',
                        90: '90 days',
                        0: 'Forever',
                      },
                      onChanged: (v) =>
                          notifier.update((x) => x.copyWith(retentionDays: v)),
                    ),
                  ),
                ],
              ),
              const SectionCard(title: 'Privacy', children: [_EncryptionRow()]),
              SectionCard(
                title: 'Appearance',
                children: [
                  SettingRow(
                    icon: Icons.brightness_6_rounded,
                    title: 'Theme',
                    trailing: _Dropdown<String>(
                      value: s.themeMode,
                      items: const {
                        'system': 'System',
                        'light': 'Light',
                        'dark': 'Dark',
                      },
                      onChanged: (v) =>
                          notifier.update((x) => x.copyWith(themeMode: v)),
                    ),
                  ),
                ],
              ),
              SectionCard(
                title: 'Capture',
                children: [
                  SwitchRow(
                    icon: s.capturePaused
                        ? Icons.pause_circle_filled_rounded
                        : Icons.pause_circle_outline_rounded,
                    title: 'Pause capture',
                    subtitle: s.capturePaused
                        ? 'Paused — nothing is recorded or synced'
                        : 'Temporarily stop recording the clipboard',
                    value: s.capturePaused,
                    onChanged: (v) =>
                        notifier.update((x) => x.copyWith(capturePaused: v)),
                  ),
                  SwitchRow(
                    icon: Icons.password_rounded,
                    title: 'Skip password-manager content',
                    subtitle:
                        'Honour the “concealed” hint set by password managers (macOS, Windows, Android 13+)',
                    value: s.skipSensitive,
                    onChanged: (v) =>
                        notifier.update((x) => x.copyWith(skipSensitive: v)),
                  ),
                  SwitchRow(
                    icon: Icons.key_off_rounded,
                    title: 'Skip keys and tokens',
                    subtitle:
                        'Never record text that looks like an API key, token, private key or connection string',
                    value: s.skipSecretLike,
                    onChanged: (v) =>
                        notifier.update((x) => x.copyWith(skipSecretLike: v)),
                  ),
                  SwitchRow(
                    icon: Icons.image_outlined,
                    title: 'Capture images',
                    subtitle: 'Up to ${s.maxInlineKb} KB per image',
                    value: s.captureImages,
                    onChanged: (v) =>
                        notifier.update((x) => x.copyWith(captureImages: v)),
                  ),
                  SwitchRow(
                    icon: Icons.content_paste_go_rounded,
                    title: 'Auto-paste incoming',
                    subtitle:
                        'Put the newest item from other devices on this clipboard',
                    value: s.writeIncomingToClipboard,
                    onChanged: (v) => notifier.update(
                      (x) => x.copyWith(writeIncomingToClipboard: v),
                    ),
                  ),
                ],
              ),
              const PermissionsSection(),
              if (PlatformInfo.isDesktop)
                SectionCard(
                  title: 'Desktop',
                  children: [
                    SwitchRow(
                      icon: Icons.power_settings_new_rounded,
                      title: 'Start at login',
                      value: s.autoStart,
                      onChanged: (v) =>
                          notifier.update((x) => x.copyWith(autoStart: v)),
                    ),
                    SwitchRow(
                      icon: Icons.visibility_off_outlined,
                      title: 'Start minimised to tray',
                      value: s.launchHidden,
                      onChanged: (v) =>
                          notifier.update((x) => x.copyWith(launchHidden: v)),
                    ),
                    SwitchRow(
                      icon: Icons.keyboard_rounded,
                      title: 'Global hotkey',
                      subtitle:
                          'Press ${shell?.hotkeyLabel ?? ''} anywhere to open history',
                      value: s.hotkeyEnabled,
                      onChanged: (v) async {
                        await notifier.update(
                          (x) => x.copyWith(hotkeyEnabled: v),
                        );
                        await shell?.setHotkeyEnabled(enabled: v);
                      },
                    ),
                  ],
                ),
              SectionCard(
                title: 'Devices',
                children: [
                  SettingRow(
                    icon: Icons.devices_rounded,
                    title: 'This device',
                    subtitle:
                        '${s.deviceName}${status.role != DeviceRole.full ? ' · ${status.role.label}' : ''} · tap to rename',
                    onTap: () async {
                      final name = await promptText(
                        context,
                        'Device name',
                        s.deviceName,
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await notifier.update(
                          (x) => x.copyWith(deviceName: name.trim()),
                        );
                      }
                    },
                  ),
                  SettingRow(
                    key: const ValueKey('manage-devices'),
                    icon: Icons.hub_rounded,
                    title: 'Manage devices',
                    subtitle: s.syncsRemotely
                        ? '${devices.length} in this group · block, remove, roles, expiry'
                        : 'Local only — no sync group',
                    onTap: () => context.push('/settings/devices'),
                  ),
                  SettingRow(
                    key: const ValueKey('add-device'),
                    icon: Icons.qr_code_2_rounded,
                    title: 'Add a device',
                    subtitle: s.syncsRemotely
                        ? 'Show a QR code or copy a pairing code'
                        : 'Connect a database first',
                    onTap: s.syncsRemotely
                        ? () => context.push('/settings/devices/pair')
                        : null,
                  ),
                  SettingRow(
                    key: const ValueKey('join-group'),
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Join another group',
                    subtitle:
                        'Scan or paste a pairing code from another device',
                    onTap: () => context.push('/settings/devices/join'),
                  ),
                ],
              ),
              SectionCard(
                title: 'Support',
                children: [
                  SettingRow(
                    icon: Icons.bug_report_outlined,
                    title: 'Diagnostics',
                    subtitle: 'Redacted logs for bug reports',
                    onTap: () => context.push('/settings/diagnostics'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: context.colors.surfaceSunken,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.colors.border),
    ),
    child: DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      isDense: true,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      style: Theme.of(context).textTheme.labelLarge,
      items: [
        for (final e in items.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    ),
  );
}

class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'OS credential store unavailable — database credentials are kept in app preferences instead of the system keychain. See Diagnostics.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptionRow extends ConsumerStatefulWidget {
  const _EncryptionRow();

  @override
  ConsumerState<_EncryptionRow> createState() => _EncryptionRowState();
}

class _EncryptionRowState extends ConsumerState<_EncryptionRow> {
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final s = ref.read(settingsProvider);
    if (!s.encryptionEnabled) {
      if (mounted) setState(() => _fingerprint = null);
      return;
    }
    final pass = await ref.read(settingsRepositoryProvider).loadPassphrase();
    if (pass == null || pass.isEmpty) return;
    final c = await ClipCipher.fromPassphrase(pass, keyScope: s.cipherKeyScope);
    final fp = await c.fingerprint();
    if (mounted) setState(() => _fingerprint = fp);
  }

  Future<void> _toggle(bool enable) async {
    final repo = ref.read(settingsRepositoryProvider);
    final notifier = ref.read(settingsProvider.notifier);
    if (!enable) {
      await notifier.update((x) => x.copyWith(encryptionEnabled: false));
      await repo.savePassphrase(null);
      await _refresh();
      return;
    }
    final pass = await promptText(
      context,
      'Encryption passphrase',
      '',
      obscure: true,
      help:
          'Use the same passphrase on every device. If you lose it, synced history cannot be read.',
    );
    if (pass == null || pass.isEmpty) return;
    await repo.savePassphrase(pass);
    await notifier.update((x) => x.copyWith(encryptionEnabled: true));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = context.colors;
    return Column(
      children: [
        SwitchRow(
          icon: s.encryptionEnabled
              ? Icons.lock_rounded
              : Icons.lock_open_rounded,
          title: 'End-to-end encryption',
          subtitle: s.encryptionEnabled
              ? 'On · key fingerprint ${_fingerprint ?? '…'} — must match on every device'
              : 'Off · the database can read your clipboard',
          value: s.encryptionEnabled,
          onChanged: _toggle,
        ),
        if (s.encryptionEnabled) ...[
          const Divider(),
          SettingRow(
            icon: Icons.key_rounded,
            title: 'Change passphrase',
            tint: c.muted,
            onTap: () => _toggle(true),
          ),
        ],
      ],
    );
  }
}

/// Simple text prompt dialog.
Future<String?> promptText(
  BuildContext context,
  String title,
  String initial, {
  bool obscure = false,
  String? help,
}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(help, style: Theme.of(ctx).textTheme.bodySmall),
              ),
            TextField(
              controller: ctl,
              obscureText: obscure,
              autofocus: true,
              autocorrect: false,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
