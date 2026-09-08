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
}
