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
/// * **Membership**: every [heartbeatInterval] (and before any sync that is
///   older than that) the engine reads the device list, refreshes its own
///   presence row, adopts the [DeviceRole] the group assigned to it, and
///   ignores clips from blocked / expired devices. If its own row says
///   blocked, removed or expired — or the row is gone after it had been
///   registered — the engine stops itself with [SyncPhase.revoked].
/// * **Auth failures** stop retries until [restart] is called with new
///   settings.
class SyncEngine {
  /// Creates an engine. Call [start] to begin.
  ///
  /// [assumeRegistered] tells the engine this device already had a row on
  /// this backend (persisted by the app after the first successful
  /// heartbeat). A missing row then means "removed and forgotten" rather
  /// than "first run".
  SyncEngine({
    required this._backend,
    required this._store,
    required this._device,
    this._cipher,
    this.pollInterval = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(minutes: 1),
    this.echoWindow = const Duration(seconds: 10),
    this.pushBatchSize = 50,
    this.assumeRegistered = false,
    SyncLogger? logger,
  }) : _log = logger ?? _noopLog;

  final SyncBackend _backend;
  final LocalStore _store;
  final Device _device;
  final ClipCipher? _cipher;
  final SyncLogger _log;

  /// Poll cadence when the backend lacks realtime.
  final Duration pollInterval;

  /// Device heartbeat / membership check cadence.
  final Duration heartbeatInterval;

  /// Window for echo suppression.
  final Duration echoWindow;

  /// Max items per upsert call.
  final int pushBatchSize;

  /// Whether a missing own row means revocation (see constructor).
  final bool assumeRegistered;

  final _statusCtl = StreamController<SyncStatus>.broadcast(sync: true);
  final _incomingCtl = StreamController<List<ClipItem>>.broadcast();
  final _devicesCtl = StreamController<List<Device>>.broadcast();
  SyncStatus _status = const SyncStatus.stopped();
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  StreamSubscription<ClipItem>? _watchSub;
  int _failures = 0;
  bool _running = false;
  Future<void>? _inFlight;
  bool _syncQueued = false;

  List<Device> _devices = const [];
  Set<String> _blockedIds = const {};
  DeviceRole _role = DeviceRole.full;
  bool _registered = false;
  DateTime? _lastMembership;

  /// Current status.
  SyncStatus get status => _status;

  /// Status changes.
  Stream<SyncStatus> get statusStream => _statusCtl.stream;

  /// Items applied from remote (already decrypted). The app uses this to
  /// refresh the list and, optionally, write the newest one to the clipboard.
  Stream<List<ClipItem>> get incoming => _incomingCtl.stream;

  /// Device list snapshots, emitted after every membership check.
  Stream<List<Device>> get devices => _devicesCtl.stream;

  /// Last known device list (empty before the first check).
  List<Device> get knownDevices => List.unmodifiable(_devices);

  /// Role the group assigned to this device.
  DeviceRole get role => _role;

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Connects, checks membership, subscribes to realtime (if any) and runs
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

    if (!await _membership()) return; // revoked

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
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _membership());

    await syncNow();
  }

  /// Stops timers and subscriptions. Safe to call twice.
  Future<void> stop() async {
    _running = false;
    _cancelTimers();
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
    await _devicesCtl.close();
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

  // --- Device management ---------------------------------------------------

  /// Re-reads the device list (and refreshes this device's presence).
  Future<List<Device>> refreshDevices() async {
    await _membership();
    return knownDevices;
  }

  /// Blocks [id]: other devices ignore its clips and it stops syncing.
  Future<void> blockDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.blocked));

  /// Re-activates a blocked device.
  Future<void> unblockDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.active));

  /// Marks [id] as removed. The row stays so the device learns about it;
  /// call [forgetDevice] later to delete the row.
  Future<void> removeDevice(String id) =>
      _patch(id, (d) => d.copyWith(status: DeviceStatus.removed));

  /// Changes what [id] may do.
  Future<void> setDeviceRole(String id, DeviceRole role) =>
      _patch(id, (d) => d.copyWith(role: role));

  /// Sets or clears (`null`) the membership expiry of [id].
  Future<void> setDeviceExpiry(String id, DateTime? expiresAt) => _patch(
    id,
    (d) => expiresAt == null
        ? d.copyWith(clearExpiresAt: true)
        : d.copyWith(expiresAt: expiresAt.toUtc()),
  );

  /// Deletes the row of [id]. Use after the device has disconnected; a
  /// device that is still running would otherwise stop with "removed".
  Future<void> forgetDevice(String id) async {
    await _backend.deleteDevice(id);
    await _membership();
  }

  /// Pre-creates a row for a device that will join with a pairing code,
  /// so the host decides its role and expiry.
  Future<void> inviteDevice({
    required String id,
    required DeviceRole role,
    DateTime? expiresAt,
  }) async {
    await _backend.updateDevice(
      Device(
        id: id,
        name: 'Pending device',
        platform: '',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        role: role,
        expiresAt: expiresAt?.toUtc(),
        pairedBy: _device.id,
      ),
    );
    await _membership();
  }

  Future<void> _patch(String id, Device Function(Device) change) async {
    var current = _devices.where((d) => d.id == id).firstOrNull;
    current ??= (await _backend.listDevices())
        .where((d) => d.id == id)
        .firstOrNull;
    if (current == null) {
      throw BackendException('Unknown device $id');
    }
    await _backend.updateDevice(change(current));
    await _membership();
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _runSync() async {
    _emit(_status.copyWith(phase: SyncPhase.syncing));
    try {
      final last = _lastMembership;
      if (last == null ||
          clock.now().toUtc().difference(last) >= heartbeatInterval) {
        if (!await _membership()) return;
      }
      if (_role.canSend) await _push();
      if (_role.canReceive) await _pull();
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
      var skipped = 0;
      for (final raw in page) {
        if (_blockedIds.contains(raw.deviceId)) {
          skipped++;
          continue; // blocked / expired device
        }
        if (raw.isTargeted && raw.targetDeviceId != _device.id) {
          skipped++;
          continue; // addressed to another device
        }
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
      _log(
        'pulled ${page.length} item(s), applied ${accepted.length}'
        '${skipped > 0 ? ', skipped $skipped' : ''}',
      );
      if (page.length < 500) return;
    }
  }

  /// Reads the device list, refreshes this device's presence and applies
  /// what the group says about it. Returns false when access was revoked.
  Future<bool> _membership() async {
    if (!_running) return false;
    final now = clock.now().toUtc();
    final presence = _device.copyWith(lastSeen: now);
    List<Device> list;
    try {
      list = await _backend.listDevices();
    } catch (e) {
      // A transient failure must not stop sync; push/pull report the
      // real error. Keep the previous device knowledge.
      _log('device list unavailable', error: e);
      return true;
    }
    try {
      final me = list.where((d) => d.id == _device.id).firstOrNull;
      if (me == null) {
        if (_registered || assumeRegistered) {
          _revoke('removed');
          return false;
        }
        await _backend.registerDevice(presence);
        list = [...list, presence];
      } else {
        if (me.status == DeviceStatus.blocked) {
          _revoke('blocked');
          return false;
        }
        if (me.status == DeviceStatus.removed) {
          _revoke('removed');
          return false;
        }
        if (me.isExpired(now)) {
          _revoke('expired');
          return false;
        }
        await _backend.registerDevice(presence);
        list = [
          for (final d in list)
            if (d.id == me.id) me.withPresence(presence) else d,
        ];
      }
      final self = list.firstWhere((d) => d.id == _device.id);
      _registered = true;
      _role = self.role;
      _blockedIds = {
        for (final d in list)
          if (d.id != self.id && !d.canSync(now)) d.id,
      };
      _devices = list;
      _lastMembership = now;
      if (!_devicesCtl.isClosed) _devicesCtl.add(knownDevices);
      if (_status.role != _role) _emit(_status.copyWith(role: _role));
      return true;
    } catch (e) {
      _log('heartbeat failed', error: e);
      return true;
    }
  }

  void _revoke(String reason) {
    _log('access revoked: $reason');
    _running = false;
    _cancelTimers();
    final sub = _watchSub;
    _watchSub = null;
    unawaited(sub?.cancel());
    _emit(
      _status.copyWith(
        phase: SyncPhase.revoked,
        revokedReason: reason,
        realtime: false,
        clearError: true,
      ),
    );
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _retryTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer = null;
    _retryTimer = null;
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
