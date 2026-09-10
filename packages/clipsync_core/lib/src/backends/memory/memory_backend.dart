import 'dart:async';

import 'package:clipsync_core/src/backend/backend_config.dart';
import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/config_field.dart';
import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/model/device.dart';
import 'package:clock/clock.dart';

/// In-process backend: no network, data lives only in memory.
///
/// Used for tests, the adapter contract suite, and as the app's
/// "Local only (no sync)" option. Supports realtime via a broadcast stream so
/// engine realtime paths are exercised in tests.
class MemoryBackend implements SyncBackend {
  /// Creates an empty backend. Pass [shared] to let several instances (one
  /// per simulated device) see the same data.
  MemoryBackend({MemoryStore? shared}) : _store = shared ?? MemoryStore();

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'memory',
    displayName: 'Local only (no sync)',
    description: 'Keep history on this device; nothing leaves it.',
    docsPath: 'docs/backends/memory.md',
    configSchema: <ConfigField>[],
    supportsRealtime: true,
    supportsBlobs: true,
  );

  final MemoryStore _store;
  bool _connected = false;

  /// Injected failure for tests: thrown by every operation while set.
  Object? failWith;

  /// Number of upsert calls (test assertions).
  int upsertCalls = 0;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  @override
  Future<void> connect(BackendConfig config) async => _connected = true;

  @override
  Future<ConnectionCheck> testConnection() async {
    _check();
    return const ConnectionCheck.success(
      'In-memory store',
      latency: Duration.zero,
    );
  }

  @override
  Future<SchemaCheck> verifySchema() async {
    _check();
    return const SchemaCheck.ready();
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    _check();
    upsertCalls++;
    for (final item in items) {
      _store.items[item.id] = item;
      _store.changes.add(item);
    }
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    _check();
    final out =
        _store.items.values
            .where((i) => i.deviceId != excludeDeviceId)
            .where((i) => cursor == null || i.updatedAt.isAfter(cursor))
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return out.take(limit).toList();
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) =>
      _store.changes.stream.where((i) => i.deviceId != excludeDeviceId);

  @override
  Future<void> tombstone(String id, DateTime now) async {
    _check();
    final existing = _store.items[id];
    if (existing == null || existing.isDeleted) return;
    final t = existing.tombstone(now);
    _store.items[id] = t;
    _store.changes.add(t);
  }

  @override
  Future<void> registerDevice(Device device) async {
    _check();
    final existing = _store.devices[device.id];
    _store.devices[device.id] = existing == null
        ? device
        : existing.withPresence(device);
  }

  @override
  Future<void> updateDevice(Device device) async {
    _check();
    _store.devices[device.id] = device;
  }

  @override
  Future<void> deleteDevice(String id) async {
    _check();
    _store.devices.remove(id);
  }

  @override
  Future<List<Device>> listDevices() async {
    _check();
    return _store.devices.values.toList();
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    _check();
    final ids =
        _store.items.values
            .where((i) => i.updatedAt.isBefore(before))
            .map((i) => i.id)
            .toList()
          ..forEach(_store.items.remove);
    return ids.length;
  }

  @override
  Future<void> dispose() async => _connected = false;

  /// Direct access for tests.
  Map<String, ClipItem> get items => _store.items;

  /// Injects a remote-side item as if another device wrote it.
  void injectRemote(ClipItem item) {
    _store.items[item.id] = item;
    _store.changes.add(item);
  }

  void _check() {
    if (!_connected) throw BackendException('Not connected');
    final f = failWith;
    if (f != null) {
      if (f is BackendException) throw f;
      throw BackendException(f.toString(), cause: f, isTransient: true);
    }
  }
}

/// Shared state behind [MemoryBackend] instances.
class MemoryStore {
  /// Items by id.
  final Map<String, ClipItem> items = {};

  /// Devices by id.
  final Map<String, Device> devices = {};

  /// Change feed.
  final StreamController<ClipItem> changes = StreamController.broadcast();

  /// Convenience: current time as UTC.
  DateTime get now => clock.now().toUtc();
}
