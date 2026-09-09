import 'dart:async';

import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/platform/clipboard_service.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the [SyncEngine], the connected backend and the clipboard capture
/// pipeline. Rebuilds when sync-affecting settings change.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// Sync lifecycle notifier; state is the engine status.
class SyncController extends Notifier<SyncStatus> {
  SyncEngine? _engine;
  SyncBackend? _backend;
  ClipboardService? _clipboard;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<List<ClipItem>>? _incomingSub;
  StreamSubscription<ClipItem>? _captureSub;
  Timer? _retention;

  @override
  SyncStatus build() {
    ref
      ..listen<AppSettings>(settingsProvider, (prev, next) {
        if (prev == null) return;
        final c = _clipboard;
        if (c != null) {
          c
            ..deviceName = next.deviceName
            ..captureImages = next.captureImages
            ..maxInlineBytes = next.maxInlineKb * 1024;
        }
        // Only a running engine needs restarting; before start() the seeded
        // secrets simply become part of the initial configuration.
        if (_engine != null && AppSettings.syncAffecting(prev, next)) {
          unawaited(restart());
        }
      })
      ..onDispose(() => unawaited(_teardown()));
    return const SyncStatus.stopped();
  }

  /// Backend currently connected (for settings screens).
  SyncBackend? get backend => _backend;

  /// Clipboard service (for share/notification entry points).
  ClipboardService? get clipboard => _clipboard;

  /// Starts sync, then clipboard capture, from current settings.
  Future<void> start() async {
    final s = ref.read(settingsProvider);
    final store = ref.read(localStoreProvider);
    // Engine first: a clipboard permission prompt on mobile must never
    // delay connecting to the backend.
    await _startEngine(s);
    if (_clipboard == null) {
      final c = ClipboardService(
        deviceId: s.deviceId,
        deviceName: s.deviceName,
        captureImages: s.captureImages,
        maxInlineBytes: s.maxInlineKb * 1024,
      );
      _captureSub = c.captured.listen((item) async {
        final inserted = await store.capture(item);
        if (inserted) {
          log.i('captured ${item.type.wire} ${item.sizeBytes}B');
          await _engine?.syncNow();
        }
      });
      _clipboard = c;
      await c.start();
    }
  }

  /// Stops and starts the engine (settings changed).
  Future<void> restart() async {
    await _stopEngine();
    await _startEngine(ref.read(settingsProvider));
  }

  /// Push + pull now.
  Future<void> syncNow() async => _engine?.syncNow();

  /// Reads the clipboard immediately (mobile entry points).
  Future<void> captureNow() async => _clipboard?.checkNow();

  /// Checks clipboard access for the Permissions section.
  Future<ClipboardProbe> probeClipboard() async =>
      _clipboard?.probe() ??
      const ClipboardProbe(
        ClipboardAccess.blocked,
        'Capture service not running.',
      );

  /// Writes [item] to the clipboard.
  Future<void> copyToClipboard(ClipItem item) async => _clipboard?.write(item);

  /// Deletes an item locally and (via outbox) remotely.
  Future<void> delete(String id) async {
    await ref.read(localStoreProvider).delete(id, DateTime.now().toUtc());
    await _engine?.syncNow();
  }

  /// Tests a backend configuration without touching the running engine.
  Future<(ConnectionCheck, SchemaCheck?)> probe(BackendConfig config) async {
    final b = ref.read(backendRegistryProvider).create(config.backendId);
    try {
      await b.connect(config);
      final conn = await b.testConnection();
      if (!conn.ok) return (conn, null);
      final schema = await b.verifySchema();
      return (conn, schema);
    } on BackendException catch (e) {
      return (ConnectionCheck.failure(e.message), null);
    } catch (e) {
      return (ConnectionCheck.failure(redactSecrets(e.toString())), null);
    } finally {
      await b.dispose();
    }
  }

  /// Runs local + remote retention.
  Future<void> runRetention() async {
    final days = ref.read(settingsProvider).retentionDays;
    if (days <= 0) return;
    final before = DateTime.now().toUtc().subtract(Duration(days: days));
    try {
      final local = await ref.read(localStoreProvider).purgeBefore(before);
      final remote = await _backend?.purgeBefore(before) ?? 0;
      log.i(
        'retention: purged $local local, $remote remote (older than $days d)',
      );
    } catch (e) {
      log.w('retention failed', error: e);
    }
  }

  Future<void> _startEngine(AppSettings s) async {
    // Never run two engines against the same store.
    if (_engine != null || _backend != null) await _stopEngine();
    final registry = ref.read(backendRegistryProvider);
    final store = ref.read(localStoreProvider);
    final descriptor = registry.descriptor(s.backendId);
    if (descriptor == null) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Unknown backend ${s.backendId}',
      );
      return;
    }
    final errors = s.backendConfig.validate(descriptor);
    if (errors.isNotEmpty) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Backend settings incomplete: ${errors.values.first}',
        authFailed: true,
      );
      return;
    }

    ClipCipher? cipher;
    if (s.encryptionEnabled) {
      final pass = await ref.read(settingsRepositoryProvider).loadPassphrase();
      if (pass == null || pass.isEmpty) {
        state = const SyncStatus(
          phase: SyncPhase.error,
          lastError: 'Encryption enabled but no passphrase set',
          authFailed: true,
        );
        return;
      }
      cipher = await ClipCipher.fromPassphrase(
        pass,
        keyScope: s.cipherKeyScope,
      );
    }

    final backend = registry.create(s.backendId);
    try {
      await backend.connect(s.backendConfig);
    } on BackendException catch (e) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: e.message,
        authFailed: e.isAuth,
      );
      await backend.dispose();
      return;
    }
    _backend = backend;

    final engine = SyncEngine(
      backend: backend,
      store: store,
      device: Device(
        id: s.deviceId,
        name: s.deviceName,
        platform: PlatformInfo.name,
        lastSeen: DateTime.now().toUtc(),
      ),
      cipher: cipher,
      pollInterval: Duration(seconds: s.pollIntervalSeconds.clamp(2, 3600)),
      logger: log.sync,
    );
    _engine = engine;
    _statusSub = engine.statusStream.listen((st) => state = st);
    _incomingSub = engine.incoming.listen((items) async {
      if (!ref.read(settingsProvider).writeIncomingToClipboard) return;
      final newest = items
          .where((i) => !i.isDeleted)
          .fold<ClipItem?>(
            null,
            (a, b) => a == null || b.createdAt.isAfter(a.createdAt) ? b : a,
          );
      if (newest != null) await _clipboard?.write(newest);
    });
    await engine.start();
    _retention = Timer.periodic(
      const Duration(hours: 12),
      (_) => runRetention(),
    );
    unawaited(runRetention());
  }

  Future<void> _stopEngine() async {
    _retention?.cancel();
    await _statusSub?.cancel();
    await _incomingSub?.cancel();
    await _engine?.dispose();
    await _backend?.dispose();
    _engine = null;
    _backend = null;
    state = const SyncStatus.stopped();
  }

  Future<void> _teardown() async {
    await _stopEngine();
    await _captureSub?.cancel();
    await _clipboard?.dispose();
    _clipboard = null;
  }
}
