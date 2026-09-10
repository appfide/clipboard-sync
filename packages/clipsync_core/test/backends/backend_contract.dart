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
          appVersion: '0.2.0',
        ),
      );
      final devices = await b.listDevices();
      final z = devices.where((x) => x.id == 'dev-z').single;
      expect(z.name, 'Z2');
      expect(z.appVersion, '0.2.0');
      expect(z.status, DeviceStatus.active);
      expect(z.role, DeviceRole.full);
    });

    test('updateDevice writes membership; heartbeat keeps it', () async {
      final id = 'dev-${const Uuid().v4()}';
      final t0 = DateTime.now().toUtc();
      final until = DateTime.utc(2030, 1, 2, 3, 4, 5);
      await b.registerDevice(
        Device(id: id, name: 'M', platform: 'test', lastSeen: t0),
      );
      await b.updateDevice(
        Device(
          id: id,
          name: 'M',
          platform: 'test',
          lastSeen: t0,
          status: DeviceStatus.blocked,
          role: DeviceRole.sendOnly,
          expiresAt: until,
          pairedBy: 'dev-a',
        ),
      );
      var m = (await b.listDevices()).firstWhere((x) => x.id == id);
      expect(m.status, DeviceStatus.blocked);
      expect(m.role, DeviceRole.sendOnly);
      expect(m.expiresAt, until);
      expect(m.pairedBy, 'dev-a');

      // A later heartbeat refreshes presence only.
      final t1 = t0.add(const Duration(minutes: 1));
      await b.registerDevice(
        Device(
          id: id,
          name: 'M renamed',
          platform: 'test',
          lastSeen: t1,
          appVersion: '9.9.9',
        ),
      );
      m = (await b.listDevices()).firstWhere((x) => x.id == id);
      expect(m.name, 'M renamed');
      expect(m.appVersion, '9.9.9');
      expect(m.status, DeviceStatus.blocked);
      expect(m.role, DeviceRole.sendOnly);
      expect(m.expiresAt, until);
      expect(m.pairedBy, 'dev-a');

      // Clearing the expiry and re-activating.
      await b.updateDevice(
        m.copyWith(status: DeviceStatus.active, clearExpiresAt: true),
      );
      m = (await b.listDevices()).firstWhere((x) => x.id == id);
      expect(m.status, DeviceStatus.active);
      expect(m.expiresAt, isNull);
    });

    test('updateDevice can pre-create a pending row', () async {
      final id = 'dev-${const Uuid().v4()}';
      await b.updateDevice(
        Device(
          id: id,
          name: 'Pending device',
          platform: '',
          lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          role: DeviceRole.receiveOnly,
          pairedBy: 'dev-a',
        ),
      );
      final m = (await b.listDevices()).firstWhere((x) => x.id == id);
      expect(m.isPending, isTrue);
      expect(m.role, DeviceRole.receiveOnly);
    });

    test('deleteDevice removes the row and is idempotent', () async {
      final id = 'dev-${const Uuid().v4()}';
      await b.registerDevice(
        Device(
          id: id,
          name: 'D',
          platform: 'test',
          lastSeen: DateTime.now().toUtc(),
        ),
      );
      await b.deleteDevice(id);
      await b.deleteDevice(id);
      expect((await b.listDevices()).map((x) => x.id), isNot(contains(id)));
    });

    test('target_device_id survives the round-trip', () async {
      final i = ClipItem.create(
        id: const Uuid().v4(),
        deviceId: 'dev-b',
        deviceName: 'B',
        type: ClipContentType.text,
        content: 'to a',
        contentHash: sha256Hex('to a'),
        sizeBytes: 4,
        now: DateTime.now().toUtc(),
        targetDeviceId: 'dev-a',
      );
      await b.upsert([i]);
      final got = (await b.pullSince(
        null,
        excludeDeviceId: 'dev-x',
      )).firstWhere((x) => x.id == i.id);
      expect(got.targetDeviceId, 'dev-a');
      final plain = textItem('broadcast', deviceId: 'dev-b');
      await b.upsert([plain]);
      final got2 = (await b.pullSince(
        null,
        excludeDeviceId: 'dev-x',
      )).firstWhere((x) => x.id == plain.id);
      expect(got2.targetDeviceId, isNull);
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
