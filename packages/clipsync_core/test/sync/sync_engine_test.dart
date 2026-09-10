import 'dart:async';

import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  late MemoryStore shared;
  late MemoryBackend backendA;
  late FakeLocalStore storeA;
  late SyncEngine engineA;

  setUp(() async {
    shared = MemoryStore();
    backendA = MemoryBackend(shared: shared);
    await backendA.connect(const BackendConfig.empty('memory'));
    storeA = FakeLocalStore();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await engineA.dispose();
    await backendA.dispose();
  });

  test('start registers device and pushes outbox', () async {
    storeA
      ..capture(textItem('one'))
      ..capture(textItem('two'));
    await engineA.start();
    expect(shared.items.length, 2);
    expect(storeA.unsynced, isEmpty);
    expect(shared.devices.keys, contains('dev-a'));
    expect(engineA.status.phase, SyncPhase.idle);
    expect(engineA.status.realtime, isTrue);
  });

  test('pull applies items from other devices and advances cursor', () async {
    final remote = textItem('from B', deviceId: 'dev-b', deviceName: 'B');
    backendA.injectRemote(remote);
    final received = <ClipItem>[];
    engineA.incoming.listen(received.addAll);
    await engineA.start();
    expect(storeA.items[remote.id]?.content, 'from B');
    expect(storeA.cursor, remote.updatedAt);
    expect(received.single.id, remote.id);
  });

  test('own items are never pulled back (excludeDeviceId)', () async {
    storeA.capture(textItem('mine'));
    await engineA.start();
    expect(storeA.items.length, 1);
    expect(storeA.unsynced, isEmpty);
  });

  test('realtime event triggers a pull', () async {
    await engineA.start();
    final remote = textItem('live', deviceId: 'dev-b');
    backendA.injectRemote(remote);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engineA.syncNow();
    expect(storeA.items.containsKey(remote.id), isTrue);
  });

  test(
    'echo suppression drops remote item whose hash we captured recently',
    () async {
      final local = textItem('same text');
      storeA.capture(local);
      await engineA.start();
      final echo = textItem('same text', deviceId: 'dev-b');
      backendA.injectRemote(echo);
      await engineA.syncNow();
      expect(storeA.items.containsKey(echo.id), isFalse);
      expect(storeA.cursor, echo.updatedAt, reason: 'cursor still advances');
    },
  );

  test('tombstones propagate', () async {
    final remote = textItem('bye', deviceId: 'dev-b');
    backendA.injectRemote(remote);
    await engineA.start();
    await backendA.tombstone(
      remote.id,
      DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
    await engineA.syncNow();
    expect(storeA.items[remote.id]!.isDeleted, isTrue);
  });

  test('encrypts on push and decrypts on pull', () async {
    final cipher = await ClipCipher.fromPassphrase('pw', keyScope: 'memory');
    await engineA.dispose();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      cipher: cipher,
      pollInterval: const Duration(hours: 1),
    );
    storeA.capture(textItem('plain'));
    await engineA.start();
    final stored = shared.items.values.single;
    expect(stored.encrypted, isTrue);
    expect(stored.content, isNot('plain'));

    // Device B with the same passphrase reads it back.
    final backendB = MemoryBackend(shared: shared);
    await backendB.connect(const BackendConfig.empty('memory'));
    final storeB = FakeLocalStore();
    final engineB = SyncEngine(
      backend: backendB,
      store: storeB,
      device: deviceB,
      cipher: await ClipCipher.fromPassphrase('pw', keyScope: 'memory'),
      pollInterval: const Duration(hours: 1),
    );
    await engineB.start();
    expect(storeB.items.values.single.content, 'plain');
    await engineB.dispose();
    await backendB.dispose();
  });

  test('wrong passphrase surfaces as auth failure and stops retries', () async {
    final cipher = await ClipCipher.fromPassphrase('pw', keyScope: 'memory');
    shared.items['x'] = await cipher.seal(
      textItem('secret', deviceId: 'dev-b'),
    );
    await engineA.dispose();
    engineA = SyncEngine(
      backend: backendA,
      store: storeA,
      device: deviceA,
      cipher: await ClipCipher.fromPassphrase('other', keyScope: 'memory'),
      pollInterval: const Duration(hours: 1),
    );
    await engineA.start();
    expect(engineA.status.phase, SyncPhase.error);
    expect(engineA.status.authFailed, isTrue);
  });

  test('transient failure schedules retry with backoff', () async {
    storeA.capture(textItem('retry me'));
    backendA.failWith = BackendException('boom', isTransient: true);
    await engineA.start();
    expect(engineA.status.phase, SyncPhase.error);
    expect(engineA.status.authFailed, isFalse);
    expect(storeA.unsynced, isNotEmpty);
    backendA.failWith = null;
    // First backoff is 2s (2^1 * 1000ms).
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(storeA.unsynced, isEmpty);
    expect(engineA.status.phase, SyncPhase.idle);
  });

  test('auth failure does not retry until restart', () async {
    storeA.capture(textItem('x'));
    backendA.failWith = BackendException('denied', isAuth: true);
    await engineA.start();
    expect(engineA.status.authFailed, isTrue);
    backendA.failWith = null;
    await engineA.syncNow(); // ignored while authFailed
    expect(storeA.unsynced, isNotEmpty);
    await engineA.restart();
    expect(storeA.unsynced, isEmpty);
  });

  test('concurrent syncNow calls coalesce', () async {
    await engineA.start();
    storeA.capture(textItem('a'));
    final f1 = engineA.syncNow();
    final f2 = engineA.syncNow();
    await Future.wait([f1, f2]);
    expect(backendA.upsertCalls, 1);
  });

  test('stop clears status and stops timers', () async {
    await engineA.start();
    await engineA.stop();
    expect(engineA.status.phase, SyncPhase.stopped);
    expect(engineA.isRunning, isFalse);
  });

  test('status stream emits transitions', () async {
    final phases = <SyncPhase>[];
    final sub = engineA.statusStream.listen((s) => phases.add(s.phase));
    await engineA.start();
    await sub.cancel();
    expect(
      phases,
      containsAllInOrder([SyncPhase.idle, SyncPhase.syncing, SyncPhase.idle]),
    );
  });

  group('membership', _membershipTests);
}

// ---------------------------------------------------------------------------
// Device management
// ---------------------------------------------------------------------------

void _membershipTests() {
  late MemoryStore shared;
  late MemoryBackend backend;
  late FakeLocalStore store;
  final revoked = <String>[];

  SyncEngine engine({bool assumeRegistered = false}) {
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: deviceA,
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      assumeRegistered: assumeRegistered,
    );
    e.statusStream.listen((s) {
      if (s.phase == SyncPhase.revoked) revoked.add(s.revokedReason!);
    });
    return e;
  }

  setUp(() async {
    revoked.clear();
    shared = MemoryStore();
    backend = MemoryBackend(shared: shared);
    await backend.connect(const BackendConfig.empty('memory'));
    store = FakeLocalStore();
  });

  tearDown(() => backend.dispose());

  test('first run registers the device with default membership', () async {
    final e = engine();
    await e.start();
    final me = shared.devices['dev-a']!;
    expect(me.status, DeviceStatus.active);
    expect(me.role, DeviceRole.full);
    expect(e.knownDevices.map((d) => d.id), contains('dev-a'));
    expect(e.status.phase, SyncPhase.idle);
    await e.dispose();
  });

  test('a blocked device stops itself with reason "blocked"', () async {
    shared.devices['dev-a'] = deviceA.copyWith(status: DeviceStatus.blocked);
    final e = engine();
    await e.start();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['blocked']);
    expect(e.isRunning, isFalse);
    // The heartbeat did not resurrect or alter the row.
    expect(shared.devices['dev-a']!.status, DeviceStatus.blocked);
    await e.dispose();
  });

  test('a removed row with assumeRegistered means revoked', () async {
    final e = engine(assumeRegistered: true);
    await e.start();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['removed']);
    expect(shared.devices.containsKey('dev-a'), isFalse);
    await e.dispose();
  });

  test('an expired membership means revoked', () async {
    shared.devices['dev-a'] = deviceA.copyWith(
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    final e = engine();
    await e.start();
    expect(revoked, ['expired']);
    await e.dispose();
  });

  test('status removed set later is noticed on the next heartbeat', () async {
    final e = engine();
    await e.start();
    expect(e.status.phase, SyncPhase.idle);
    shared.devices['dev-a'] = shared.devices['dev-a']!.copyWith(
      status: DeviceStatus.removed,
    );
    await e.refreshDevices();
    expect(e.status.phase, SyncPhase.revoked);
    expect(revoked, ['removed']);
    await e.dispose();
  });

  test('heartbeat keeps membership fields set by another device', () async {
    final e = engine();
    await e.start();
    // Manager changes our role and expiry directly in the backend.
    final until = DateTime.now().toUtc().add(const Duration(days: 1));
    await backend.updateDevice(
      shared.devices['dev-a']!.copyWith(
        role: DeviceRole.sendOnly,
        expiresAt: until,
        pairedBy: 'dev-b',
      ),
    );
    await e.refreshDevices();
    final me = shared.devices['dev-a']!;
    expect(me.role, DeviceRole.sendOnly);
    expect(me.expiresAt, until);
    expect(me.pairedBy, 'dev-b');
    expect(e.role, DeviceRole.sendOnly);
    expect(e.status.role, DeviceRole.sendOnly);
    await e.dispose();
  });

  test('clips from blocked devices are skipped on pull', () async {
    shared.devices['dev-b'] = deviceB.copyWith(status: DeviceStatus.blocked);
    shared.devices['dev-c'] = Device(
      id: 'dev-c',
      name: 'C',
      platform: 'test',
      lastSeen: DateTime.now().toUtc(),
    );
    backend
      ..injectRemote(textItem('from blocked', deviceId: 'dev-b'))
      ..injectRemote(textItem('from c', deviceId: 'dev-c'));
    final e = engine();
    await e.start();
    expect(store.items.values.map((i) => i.content), ['from c']);
    await e.dispose();
  });

  test('targeted clips reach only the addressed device', () async {
    final forMe = ClipItem.create(
      id: 'for-a',
      deviceId: 'dev-b',
      deviceName: 'B',
      type: ClipContentType.text,
      content: 'for a',
      contentHash: sha256Hex('for a'),
      sizeBytes: 5,
      now: DateTime.now().toUtc(),
      targetDeviceId: 'dev-a',
    );
    final forOther = ClipItem.create(
      id: 'for-c',
      deviceId: 'dev-b',
      deviceName: 'B',
      type: ClipContentType.text,
      content: 'for c',
      contentHash: sha256Hex('for c'),
      sizeBytes: 5,
      now: DateTime.now().toUtc(),
      targetDeviceId: 'dev-c',
    );
    backend
      ..injectRemote(forMe)
      ..injectRemote(forOther);
    final e = engine();
    await e.start();
    expect(store.items.keys, ['for-a']);
    // Cursor still advanced past the skipped item.
    expect(store.cursor, isNotNull);
    await e.dispose();
  });

  test('send-only role pushes but never pulls', () async {
    shared.devices['dev-a'] = deviceA.copyWith(role: DeviceRole.sendOnly);
    backend.injectRemote(textItem('remote', deviceId: 'dev-b'));
    store.capture(textItem('mine'));
    final e = engine();
    await e.start();
    expect(store.unsynced, isEmpty, reason: 'push happened');
    expect(store.items.length, 1, reason: 'nothing pulled');
    expect(e.role, DeviceRole.sendOnly);
    await e.dispose();
  });

  test('receive-only role pulls but never pushes', () async {
    shared.devices['dev-a'] = deviceA.copyWith(role: DeviceRole.receiveOnly);
    backend.injectRemote(textItem('remote', deviceId: 'dev-b'));
    final mine = textItem('mine');
    store.capture(mine);
    final e = engine();
    await e.start();
    expect(store.unsynced, {mine.id}, reason: 'outbox untouched');
    expect(shared.items.containsKey(mine.id), isFalse);
    expect(store.items.length, 2, reason: 'remote applied');
    await e.dispose();
  });

  test('management helpers write through and refresh the list', () async {
    shared.devices['dev-b'] = deviceB;
    final e = engine();
    await e.start();
    final snapshots = <List<Device>>[];
    e.devices.listen(snapshots.add);

    await e.blockDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.blocked);
    await e.unblockDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.active);
    await e.setDeviceRole('dev-b', DeviceRole.receiveOnly);
    expect(shared.devices['dev-b']!.role, DeviceRole.receiveOnly);
    final until = DateTime.now().toUtc().add(const Duration(hours: 2));
    await e.setDeviceExpiry('dev-b', until);
    expect(shared.devices['dev-b']!.expiresAt, until);
    await e.setDeviceExpiry('dev-b', null);
    expect(shared.devices['dev-b']!.expiresAt, isNull);
    await e.removeDevice('dev-b');
    expect(shared.devices['dev-b']!.status, DeviceStatus.removed);
    await e.forgetDevice('dev-b');
    expect(shared.devices.containsKey('dev-b'), isFalse);
    await e.inviteDevice(id: 'dev-new', role: DeviceRole.sendOnly);
    final invited = shared.devices['dev-new']!;
    expect(invited.isPending, isTrue);
    expect(invited.role, DeviceRole.sendOnly);
    expect(invited.pairedBy, 'dev-a');
    expect(snapshots, isNotEmpty);
    expect(e.knownDevices.map((d) => d.id), containsAll(['dev-a', 'dev-new']));
    expect(() => e.blockDevice('nope'), throwsA(isA<BackendException>()));
    await e.dispose();
  });

  test('a joining device adopts the invited row and its role', () async {
    // Host pre-created the row; the joiner (dev-a) heartbeats into it.
    shared.devices['dev-a'] = Device(
      id: 'dev-a',
      name: 'Pending device',
      platform: '',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      role: DeviceRole.receiveOnly,
      pairedBy: 'dev-host',
    );
    final e = engine();
    await e.start();
    final me = shared.devices['dev-a']!;
    expect(me.name, 'A');
    expect(me.platform, 'test');
    expect(me.isPending, isFalse);
    expect(me.role, DeviceRole.receiveOnly);
    expect(me.pairedBy, 'dev-host');
    expect(e.role, DeviceRole.receiveOnly);
    await e.dispose();
  });

  test('device list failure does not stop syncing', () async {
    final e = engine();
    await e.start();
    backend.failWith = BackendException('boom', isTransient: true);
    await e.refreshDevices();
    expect(e.status.phase, isNot(SyncPhase.revoked));
    backend.failWith = null;
    await e.dispose();
  });
}
