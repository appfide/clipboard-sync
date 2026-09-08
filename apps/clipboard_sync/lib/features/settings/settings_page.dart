import 'dart:async';

import 'package:clipboard_sync/core/build_info.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// All preferences.
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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Sync'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Database'),
            subtitle: Text(descriptor?.displayName ?? s.backendId),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/backend'),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Poll interval'),
            subtitle: Text(
              descriptor?.supportsRealtime ?? false
                  ? 'Realtime backend — used only as fallback'
                  : 'Every ${s.pollIntervalSeconds} s',
            ),
            trailing: DropdownButton<int>(
              value: s.pollIntervalSeconds,
              underline: const SizedBox.shrink(),
              items: const [2, 5, 10, 30, 60, 300]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v s')))
                  .toList(),
              onChanged: (v) => v == null
                  ? null
                  : notifier.update((x) => x.copyWith(pollIntervalSeconds: v)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Keep history for'),
            trailing: DropdownButton<int>(
              value: s.retentionDays,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 day')),
                DropdownMenuItem(value: 7, child: Text('7 days')),
                DropdownMenuItem(value: 30, child: Text('30 days')),
                DropdownMenuItem(value: 90, child: Text('90 days')),
                DropdownMenuItem(value: 0, child: Text('Forever')),
              ],
              onChanged: (v) => v == null
                  ? null
                  : notifier.update((x) => x.copyWith(retentionDays: v)),
            ),
          ),
          const _Header('Encryption'),
          const _EncryptionTile(),
          const _Header('Capture'),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: const Text('Capture images'),
            subtitle: Text('Up to ${s.maxInlineKb} KB'),
            value: s.captureImages,
            onChanged: (v) =>
                notifier.update((x) => x.copyWith(captureImages: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.content_paste_go),
            title: const Text('Auto-paste incoming'),
            subtitle: const Text(
              'Put the newest item from other devices on this clipboard',
            ),
            value: s.writeIncomingToClipboard,
            onChanged: (v) =>
                notifier.update((x) => x.copyWith(writeIncomingToClipboard: v)),
          ),
          if (PlatformInfo.isMobile)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Mobile capture'),
              subtitle: Text(
                'The OS only allows reading the clipboard while the app is open. Open the app (or tap Sync) after copying.',
              ),
            ),
          if (PlatformInfo.isDesktop) ...[
            const _Header('Desktop'),
            SwitchListTile(
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('Start at login'),
              value: s.autoStart,
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(autoStart: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Start minimised to tray'),
              value: s.launchHidden,
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(launchHidden: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.keyboard),
              title: const Text('Global hotkey'),
              subtitle: Text(shell?.hotkeyLabel ?? ''),
              value: s.hotkeyEnabled,
              onChanged: (v) async {
                await notifier.update((x) => x.copyWith(hotkeyEnabled: v));
                await shell?.setHotkeyEnabled(enabled: v);
              },
            ),
          ],
          const _Header('This device'),
          ValueListenableBuilder<bool>(
            valueListenable: ref.watch(secretStoreProvider).degraded,
            builder: (context, degraded, _) => degraded
                ? ListTile(
                    leading: Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('OS credential store unavailable'),
                    subtitle: const Text(
                      'Database credentials are kept in app preferences instead of the system keychain. See Diagnostics.',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Device name'),
            subtitle: Text(s.deviceName),
            onTap: () async {
              final name = await _prompt(context, 'Device name', s.deviceName);
              if (name != null && name.trim().isNotEmpty) {
                await notifier.update(
                  (x) => x.copyWith(deviceName: name.trim()),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Diagnostics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/diagnostics'),
          ),
          const _Header('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Clipboard Sync'),
            subtitle: const Text(
              'Version ${BuildInfo.version} (${BuildInfo.gitSha}) · MIT · Appfide',
            ),
            onTap: () => launchUrl(
              Uri.parse(BuildInfo.repoUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EncryptionTile extends ConsumerStatefulWidget {
  const _EncryptionTile();

  @override
  ConsumerState<_EncryptionTile> createState() => _EncryptionTileState();
}

class _EncryptionTileState extends ConsumerState<_EncryptionTile> {
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final s = ref.read(settingsProvider);
    if (!s.encryptionEnabled) {
      setState(() => _fingerprint = null);
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
    final pass = await _prompt(
      context,
      'Encryption passphrase',
      '',
      obscure: true,
      help:
          'Use the same passphrase on every device. Losing it makes synced history unreadable.',
    );
    if (pass == null || pass.isEmpty) return;
    await repo.savePassphrase(pass);
    await notifier.update((x) => x.copyWith(encryptionEnabled: true));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('End-to-end encryption'),
          subtitle: Text(
            s.encryptionEnabled
                ? 'On · key fingerprint ${_fingerprint ?? '…'} (must match on all devices)'
                : 'Off · the database can read your clipboard',
          ),
          value: s.encryptionEnabled,
          onChanged: _toggle,
        ),
        if (s.encryptionEnabled)
          ListTile(
            leading: const SizedBox.shrink(),
            title: const Text('Change passphrase'),
            onTap: () => _toggle(true),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

Future<String?> _prompt(
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
