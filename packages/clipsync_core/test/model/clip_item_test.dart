import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

void main() {
  group('ClipItem', () {
    final now = DateTime.utc(2026, 9, 8, 12);
    final item = ClipItem.create(
      id: 'id-1',
      deviceId: 'd',
      deviceName: 'Mac',
      type: ClipContentType.url,
      content: 'https://example.com',
      contentHash: sha256Hex('https://example.com'),
      sizeBytes: 19,
      now: now,
    );

    test('round-trips through toMap/fromMap', () {
      final back = ClipItem.fromMap(item.toMap());
      expect(back, equals(item));
      expect(back.type, ClipContentType.url);
      expect(back.createdAt, now);
      expect(back.isDeleted, isFalse);
    });

    test('accepts DateTime and epoch-ms timestamps from backends', () {
      final m = item.toMap()
        ..['created_at'] = now
        ..['updated_at'] = now.millisecondsSinceEpoch
        ..['size_bytes'] = '19';
      final back = ClipItem.fromMap(m);
      expect(back.createdAt, now);
      expect(back.updatedAt, now);
      expect(back.sizeBytes, 19);
    });

    test('tombstone sets deleted_at and bumps updated_at', () {
      final later = now.add(const Duration(minutes: 1));
      final t = item.tombstone(later);
      expect(t.isDeleted, isTrue);
      expect(t.updatedAt, later);
      expect(t.toMap()['deleted_at'], later.toIso8601String());
    });

    test('unknown content_type falls back to text', () {
      expect(ClipContentType.fromWire('weird'), ClipContentType.text);
      expect(ClipContentType.image.isBinary, isTrue);
    });
  });

  group('Device', () {
    test('round-trips', () {
      final d = Device(
        id: 'x',
        name: 'Phone',
        platform: 'android',
        lastSeen: DateTime.utc(2026),
      );
      expect(Device.fromMap(d.toMap()).lastSeen, d.lastSeen);
    });
  });
}
