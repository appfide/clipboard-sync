import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../helpers/fakes.dart';

/// Contract every [SyncBackend] must satisfy. Run against the in-memory
/// backend in CI and against live databases locally by setting
/// `CLIPSYNC_TEST_<BACKEND>_*` environment variables (see
/// `live_backends_test.dart`).
void runBackendContractTests(
  String name,
  Future<SyncBackend> Function() create, {
  bool realtime = false,
}) {
  group('$name contract', () {
    late SyncBackend b;
    setUp(() async => b = await create());
    tearDown(() => b.dispose());

    test('testConnection and verifySchema succeed', () async {
      final c = await b.testConnection();
      expect(c.ok, isTrue, reason: c.message);
      final s = await b.verifySchema();
      expect(s.ok, isTrue, reason: '${s.missing} ${s.hint}');
    });

    test('upsert is idempotent and pullSince orders by updated_at', () async {
      final t0 = DateTime.now().toUtc();
      final a = textItem(
        'a',
        deviceId: 'dev-b',
        at: t0.add(const Duration(seconds: 1)),
      );
      final c = textItem(
        'c',
        deviceId: 'dev-b',
        at: t0.add(const Duration(seconds: 3)),
      );
      final bb = textItem(
        'b',
        deviceId: 'dev-b',
        at: t0.add(const Duration(seconds: 2)),
      );
      await b.upsert([a, c]);
      await b.upsert([bb, a]);
      final all = await b.pullSince(t0, excludeDeviceId: 'dev-a');
      final ids = all
          .where((i) => [a.id, bb.id, c.id].contains(i.id))
          .map((i) => i.id)
          .toList();
      expect(ids, [a.id, bb.id, c.id]);
      final later = await b.pullSince(bb.updatedAt, excludeDeviceId: 'dev-a');
      expect(later.map((i) => i.id), [c.id]);
    });

    test('pullSince excludes own device', () async {
      final mine = textItem('mine');
      await b.upsert([mine]);
      final got = await b.pullSince(null, excludeDeviceId: 'dev-a');
      expect(got.map((i) => i.id), isNot(contains(mine.id)));
    });

    test('tombstone is visible to pull and idempotent', () async {
      final i = textItem('del', deviceId: 'dev-b');
      await b.upsert([i]);
      final now = DateTime.now().toUtc().add(const Duration(seconds: 5));
      await b.tombstone(i.id, now);
      await b.tombstone(i.id, now);
      await b.tombstone(const Uuid().v4(), now); // unknown id is a no-op
      final got = await b.pullSince(i.updatedAt, excludeDeviceId: 'dev-a');
      final t = got.firstWhere((x) => x.id == i.id);
      expect(t.isDeleted, isTrue);
      expect(t.content, isEmpty);
    });

    test('encrypted payload survives round-trip untouched', () async {
      final cipher = ClipCipher.fromKeyBytes(List<int>.filled(32, 7));
      final sealed = await cipher.seal(textItem('enc', deviceId: 'dev-b'));
      await b.upsert([sealed]);
      final got = (await b.pullSince(
        null,
        excludeDeviceId: 'dev-a',
      )).firstWhere((x) => x.id == sealed.id);
      expect(got.encrypted, isTrue);
      expect(got.nonce, sealed.nonce);
      expect((await cipher.open(got)).content, 'enc');
    });

    test('registerDevice upserts and listDevices returns it', () async {
      final d = Device(
        id: 'dev-z',
        name: 'Z',
        platform: 'test',
        lastSeen: DateTime.now().toUtc(),
      );
      await b.registerDevice(d);
      await b.registerDevice(
        Device(
          id: 'dev-z',
          name: 'Z2',
          platform: 'test',
          lastSeen: DateTime.now().toUtc(),
        ),
      );
      final devices = await b.listDevices();
      expect(devices.where((x) => x.id == 'dev-z').single.name, 'Z2');
    });

    test('purgeBefore removes old rows', () async {
      final old = textItem('old', deviceId: 'dev-b', at: DateTime.utc(2000));
      await b.upsert([old]);
      final n = await b.purgeBefore(DateTime.utc(2001));
      expect(n, anyOf(-1, greaterThanOrEqualTo(1)));
      final got = await b.pullSince(null, excludeDeviceId: 'dev-a');
      expect(got.map((i) => i.id), isNot(contains(old.id)));
    });

    if (realtime) {
      test('watch emits items written by other devices', () async {
        final events = <ClipItem>[];
        final sub = b.watch(excludeDeviceId: 'dev-a').listen(events.add);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final i = textItem('rt', deviceId: 'dev-b');
        await b.upsert([i]);
        await Future<void>.delayed(const Duration(seconds: 2));
        await sub.cancel();
        expect(events.map((e) => e.id), contains(i.id));
      });
    }
  });
}
