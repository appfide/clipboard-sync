import 'dart:async';

import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/features/devices/device_widgets.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Joiner side of pairing: scan or paste a code, type the PIN, review what
/// the code grants, join.
class JoinPage extends ConsumerStatefulWidget {
  /// Creates the page. [onboarding] routes to the history on success.
  const JoinPage({this.onboarding = false, super.key});

  /// Wizard mode.
  final bool onboarding;

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _passphrase = TextEditingController();
  MobileScannerController? _scanner;
  bool _busy = false;
  String? _error;
  PairingPayload? _payload;

  bool get _canScan => PlatformInfo.isMobile;

  @override
  void initState() {
    super.initState();
    if (_canScan) {
      _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _passphrase.dispose();
    unawaited(_scanner?.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && PairingCodec.looksLikeCode(v)) {
        unawaited(_scanner?.stop());
        setState(() {
          _code.text = v;
          _error = null;
        });
        return;
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (PairingCodec.looksLikeCode(t)) {
      setState(() {
        _code.text = t;
        _error = null;
      });
    } else {
      setState(() => _error = 'The clipboard does not hold a pairing code.');
    }
  }

  Future<void> _unlock() async {
    final pinErr = PairingCodec.validatePin(_pin.text);
    if (pinErr != null) {
      setState(() => _error = pinErr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await PairingCodec.open(
        _code.text,
        _pin.text,
        now: DateTime.now().toUtc(),
      );
      setState(() => _payload = p);
    } on PairingException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final p = _payload!;
    if (p.needsPassphrase && _passphrase.text.isEmpty) {
      setState(() => _error = 'Enter the encryption passphrase.');
      return;
    }
    final s = ref.read(settingsProvider);
    if (s.syncsRemotely) {
      final ok = await confirm(
        context,
        title: 'Replace current database?',
        message:
            'This device is connected to another sync group. Joining replaces those settings; local history is kept.',
        action: 'Join',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(syncControllerProvider.notifier)
          .joinFromPairing(p, passphrase: _passphrase.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Joined ${p.hostDeviceName}’s group')),
        );
      if (widget.onboarding) {
        context.go('/');
      } else {
        context.pop();
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final registry = ref.watch(backendRegistryProvider);
    final payload = _payload;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a sync group'),
        leading: widget.onboarding
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/onboarding'),
              )
            : null,
      ),
      body: ContentColumn(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (payload == null) ...[
              Text(
                'On a device that already syncs, open Settings → Devices → Add a device. Then scan its QR code here, or paste the copied code.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_canScan && _code.text.isEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  child: SizedBox(
                    height: 260,
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                      errorBuilder: (_, error) => Container(
                        color: c.surfaceSunken,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Camera unavailable (${error.errorCode.name}). Paste the code instead.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const ValueKey('pairing-code'),
                controller: _code,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  labelText: 'Pairing code',
                  hintText: '${PairingCodec.prefix}…',
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pairing-pin'),
                controller: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
                  LengthLimitingTextInputFormatter(9),
                ],
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  hintText: '1234 5678',
                ),
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const ValueKey('join-error'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('unlock-code'),
                onPressed: _busy || _code.text.trim().isEmpty ? null : _unlock,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(_busy ? 'Checking…' : 'Unlock code'),
              ),
            ] else ...[
              SectionCard(
                title: 'You are about to join',
                children: [
                  _Row(
                    Icons.devices_rounded,
                    'Invited by',
                    payload.hostDeviceName.isEmpty
                        ? 'Another device'
                        : payload.hostDeviceName,
                  ),
                  _Row(
                    Icons.storage_rounded,
                    'Database',
                    registry.descriptor(payload.backendId)?.displayName ??
                        payload.backendId,
                  ),
                  _Row(
                    payload.isSignedGroup
                        ? Icons.verified_user_rounded
                        : Icons.gpp_maybe_rounded,
                    'Group security',
                    payload.isSignedGroup
                        ? 'Signed · admin key ${keyFingerprint(payload.adminPub!)}'
                              '${payload.adminKey != null ? ' · this device becomes an admin' : ''}'
                        : 'Not signed (legacy) — anyone with the credentials can pose as a device',
                  ),
                  _Row(Icons.swap_vert_rounded, 'Role', payload.role.label),
                  _Row(
                    Icons.schedule_rounded,
                    'Access',
                    payload.expiresAt == null
                        ? 'No expiry'
                        : 'Until ${payload.expiresAt!.toLocal()}'
                              .split('.')
                              .first,
                  ),
                  _Row(
                    payload.encryption
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    'Encryption',
                    payload.encryption
                        ? (payload.passphraseDelivered
                              ? 'On · key delivered securely to this device'
                              : 'On · passphrase needed')
                        : 'Off',
                  ),
                ],
              ),
              if (payload.needsPassphrase) ...[
                TextField(
                  key: const ValueKey('join-passphrase'),
                  controller: _passphrase,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Encryption passphrase',
                    helperText:
                        'The same passphrase the other devices use. Without it synced history cannot be read.',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    key: const ValueKey('join-error'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _payload = null;
                            _error = null;
                          }),
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const ValueKey('join-group'),
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(_busy ? 'Joining…' : 'Join'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SettingRow(
    icon: icon,
    title: label,
    subtitle: value,
    tint: context.colors.muted,
  );
}
