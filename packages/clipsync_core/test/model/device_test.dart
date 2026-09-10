import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);

  test('fromMap tolerates rows written by 0.1.0 (no membership fields)', () {
    final d = Device.fromMap({
      'id': 'x',
      'name': 'Old',
      'platform': 'linux',
      'last_seen': now.toIso8601String(),
    });
    expect(d.status, DeviceStatus.active);
    expect(d.role, DeviceRole.full);
    expect(d.expiresAt, isNull);
    expect(d.pairedBy, isNull);
    expect(d.canSync(now), isTrue);
  });

  test('toMap / fromMap round-trip keeps every field', () {
    final d = Device(
      id: 'x',
      name: 'Phone',
      platform: 'android',
      lastSeen: now,
      status: DeviceStatus.blocked,
      role: DeviceRole.sendOnly,
      expiresAt: now.add(const Duration(days: 1)),
      pairedBy: 'host',
      appVersion: '0.2.0',
    );
    final back = Device.fromMap(d.toMap());
    expect(back.status, DeviceStatus.blocked);
    expect(back.role, DeviceRole.sendOnly);
    expect(back.expiresAt, d.expiresAt);
    expect(back.pairedBy, 'host');
    expect(back.appVersion, '0.2.0');
    expect(back.lastSeen, now);
  });

  test('unknown wire values fall back to safe defaults', () {
    expect(DeviceStatus.fromWire('weird'), DeviceStatus.active);
    expect(DeviceRole.fromWire(null), DeviceRole.full);
  });

  test('expiry and status drive canSync', () {
    final base = Device(id: 'x', name: 'n', platform: 'p', lastSeen: now);
    expect(base.canSync(now), isTrue);
    expect(
      base
          .copyWith(expiresAt: now.subtract(const Duration(seconds: 1)))
          .canSync(now),
      isFalse,
    );
    expect(
      base
          .copyWith(expiresAt: now.add(const Duration(seconds: 1)))
          .canSync(now),
      isTrue,
    );
    expect(base.copyWith(status: DeviceStatus.blocked).canSync(now), isFalse);
    expect(base.copyWith(status: DeviceStatus.removed).canSync(now), isFalse);
    expect(
      base.copyWith(expiresAt: now).copyWith(clearExpiresAt: true).expiresAt,
      isNull,
    );
  });

  test('withPresence keeps membership fields', () {
    final managed = Device(
      id: 'x',
      name: 'Old name',
      platform: 'macos',
      lastSeen: now.subtract(const Duration(hours: 1)),
      status: DeviceStatus.blocked,
      role: DeviceRole.receiveOnly,
      expiresAt: now.add(const Duration(days: 2)),
      pairedBy: 'host',
    );
    final heartbeat = Device(
      id: 'x',
      name: 'New name',
      platform: 'macos',
      lastSeen: now,
      appVersion: '0.2.0',
    );
    final merged = managed.withPresence(heartbeat);
    expect(merged.name, 'New name');
    expect(merged.lastSeen, now);
    expect(merged.appVersion, '0.2.0');
    expect(merged.status, DeviceStatus.blocked);
    expect(merged.role, DeviceRole.receiveOnly);
    expect(merged.expiresAt, managed.expiresAt);
    expect(merged.pairedBy, 'host');
  });

  test('presence and membership keys partition toMap', () {
    final keys = Device(
      id: 'x',
      name: 'n',
      platform: 'p',
      lastSeen: now,
    ).toMap().keys.toSet();
    expect(keys, Device.presenceKeys.union(Device.membershipKeys));
  });

  test('online and pending helpers', () {
    final d = Device(id: 'x', name: 'n', platform: 'p', lastSeen: now);
    expect(d.isOnline(now.add(const Duration(minutes: 1))), isTrue);
    expect(d.isOnline(now.add(const Duration(minutes: 10))), isFalse);
    expect(d.isPending, isFalse);
    expect(
      d
          .copyWith(
            lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          )
          .isPending,
      isTrue,
    );
  });

  test('ClipItem carries target_device_id', () {
    final i = ClipItem.create(
      id: 'i',
      deviceId: 'a',
      deviceName: 'A',
      type: ClipContentType.text,
      content: 'hi',
      contentHash: sha256Hex('hi'),
      sizeBytes: 2,
      now: now,
      targetDeviceId: 'b',
    );
    expect(i.isTargeted, isTrue);
    expect(ClipItem.fromMap(i.toMap()).targetDeviceId, 'b');
    expect(
      ClipItem.fromMap(i.toMap()..['target_device_id'] = '').isTargeted,
      isFalse,
    );
  });
}
