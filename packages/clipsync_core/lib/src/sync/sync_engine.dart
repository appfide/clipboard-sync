import 'dart:async';
import 'dart:math';

import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/crypto/clip_cipher.dart';
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/model/device.dart';
import 'package:clipsync_core/src/sync/local_store.dart';
import 'package:clipsync_core/src/sync/sync_status.dart';
import 'package:clipsync_core/src/util/redact.dart';
import 'package:clock/clock.dart';

/// Log sink; the app wires this to its logger. Messages are pre-redacted.
typedef SyncLogger = void Function(String message, {Object? error});

/// Drives replication between a [LocalStore] and a [SyncBackend].
///
/// * **Push**: drains the outbox in batches, encrypting when a [ClipCipher]
///   is set, with exponential backoff on transient errors.
/// * **Pull**: `pullSince(cursor)` on start, on demand, on a timer when the
///   backend has no realtime, and after every realtime event (realtime is a
///   *hint*; the cursor query is the source of truth so nothing is missed).
/// * **Echo suppression**: incoming items whose hash was captured locally in
///   the last [echoWindow] are dropped.
/// * **Auth failures** stop retries until [restart] is called with new
///   settings.
class SyncEngine {
  /// Creates an engine. Call [start] to begin.
  SyncEngine({
    required this._backend,
    required this._store,
    required this._device,
    this._cipher,
    this.pollInterval = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(minutes: 5),
    this.echoWindow = const Duration(seconds: 10),
    this.pushBatchSize = 50,
    SyncLogger? logger,
  }) : _log = logger ?? _noopLog;

  final SyncBackend _backend;
  final LocalStore _store;
  final Device _device;
  final ClipCipher? _cipher;
  final SyncLogger _log;

  /// Poll cadence when the backend lacks realtime.
  final Duration pollInterval;

  /// Device heartbeat cadence.
  final Duration heartbeatInterval;

  /// Window for echo suppression.
  final Duration echoWindow;

  /// Max items per upsert call.
  final int pushBatchSize;

  final _statusCtl = StreamController<SyncStatus>.broadcast(sync: true);
  final _incomingCtl = StreamController<List<ClipItem>>.broadcast();
  SyncStatus _status = const SyncStatus.stopped();
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  StreamSubscription<ClipItem>? _watchSub;
  int _failures = 0;
  bool _running = false;
  Future<void>? _inFlight;
  bool _syncQueued = false;

  /// Current status.
  SyncStatus get status => _status;

  /// Status changes.
  Stream<SyncStatus> get statusStream => _statusCtl.stream;

  /// Items applied from remote (already decrypted). The app uses this to
  /// refresh the list and, optionally, write the newest one to the clipboard.
  Stream<List<ClipItem>> get incoming => _incomingCtl.stream;

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Connects, registers the device, subscribes to realtime (if any) and runs
  /// an initial sync.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _failures = 0;
    _emit(
      _status.copyWith(
        phase: SyncPhase.idle,
        authFailed: false,
        clearError: true,
      ),
    );

    if (_backend.descriptor.supportsRealtime) {
      _watchSub = _backend
          .watch(excludeDeviceId: _device.id)
          .listen(
            (_) => syncNow(),
            onError: (Object e) => _log('realtime stream error', error: e),
          );
      _emit(_status.copyWith(realtime: true));
    } else {
      _pollTimer = Timer.periodic(pollInterval, (_) => syncNow());
    }
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _heartbeat());

    await _heartbeat();
    await syncNow();
  }

  /// Stops timers and subscriptions. Safe to call twice.
  Future<void> stop() async {
    _running = false;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _retryTimer?.cancel();
    await _watchSub?.cancel();
    _watchSub = null;
    await _inFlight;
    _emit(const SyncStatus.stopped());
  }

  /// Stops and starts again (after settings changed).
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Releases the engine (does not dispose the backend).
  Future<void> dispose() async {
    await stop();
    await _statusCtl.close();
    await _incomingCtl.close();
  }

  /// Push the outbox then pull remote changes. Coalesces concurrent calls:
  /// if a sync is in flight, one more runs after it.
  Future<void> syncNow() {
    if (!_running || _status.authFailed) return Future.value();
    if (_inFlight != null) {
      _syncQueued = true;
      return _inFlight!;
    }
    _inFlight = _runSync().whenComplete(() {
      _inFlight = null;
      if (_syncQueued) {
        _syncQueued = false;
        unawaited(syncNow());
      }
    });
    return _inFlight!;
  }

  Future<void> _runSync() async {
    _emit(_status.copyWith(phase: SyncPhase.syncing));
    try {
      await _push();
      await _pull();
      _failures = 0;
      final pending = (await _store.pendingOutbox(limit: 1)).length;
      _emit(
        _status.copyWith(
          phase: SyncPhase.idle,
          lastSyncAt: clock.now().toUtc(),
          pendingCount: pending,
          clearError: true,
        ),
      );
    } on BackendException catch (e) {
      _onError(e.message, e, isAuth: e.isAuth);
    } on CipherException catch (e) {
      // Wrong passphrase: behaves like auth — user must fix settings.
      _onError(e.message, e, isAuth: true);
    } catch (e) {
      _onError(e.toString(), e);
    }
  }

  Future<void> _push() async {
    while (true) {
      final batch = await _store.pendingOutbox(limit: pushBatchSize);
      if (batch.isEmpty) return;
      final sealed = <ClipItem>[];
      for (final item in batch) {
        sealed.add(_cipher == null ? item : await _cipher.seal(item));
      }
      await _backend.upsert(sealed);
      await _store.markSynced(batch.map((i) => i.id));
      _log('pushed ${batch.length} item(s)');
      if (batch.length < pushBatchSize) return;
    }
  }

  Future<void> _pull() async {
    var cursor = await _store.loadCursor();
    while (true) {
      final page = await _backend.pullSince(
        cursor,
        excludeDeviceId: _device.id,
      );
      if (page.isEmpty) return;

      final accepted = <ClipItem>[];
      final echoSince = clock.now().toUtc().subtract(echoWindow);
      for (final raw in page) {
        final item = _cipher == null ? raw : await _cipher.open(raw);
        if (!item.isDeleted &&
            await _store.hasRecentHash(item.contentHash, echoSince)) {
          continue; // our own clipboard write bouncing back via another device
        }
        accepted.add(item);
      }
      if (accepted.isNotEmpty) {
        await _store.applyRemote(accepted);
        _incomingCtl.add(accepted);
      }
      cursor = page
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _store.saveCursor(cursor);
      _log('pulled ${page.length} item(s), applied ${accepted.length}');
      if (page.length < 500) return;
    }
  }

  Future<void> _heartbeat() async {
    try {
      await _backend.registerDevice(
        Device(
          id: _device.id,
          name: _device.name,
          platform: _device.platform,
          lastSeen: clock.now().toUtc(),
        ),
      );
    } catch (e) {
      _log('heartbeat failed', error: e);
    }
  }

  void _onError(String message, Object error, {bool isAuth = false}) {
    final msg = redactSecrets(message);
    _log('sync failed: $msg', error: error);
    _emit(
      _status.copyWith(
        phase: SyncPhase.error,
        lastError: msg,
        authFailed: isAuth,
      ),
    );
    if (isAuth || !_running) return;
    _failures++;
    final delay = Duration(
      milliseconds: min(60000, 1000 * pow(2, min(_failures, 6)).toInt()),
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, syncNow);
  }

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  static void _noopLog(String message, {Object? error}) {}
}
