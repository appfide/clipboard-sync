import 'package:clipsync_core/clipsync_core.dart';

/// In-memory [LocalStore] mirroring the drift implementation's semantics.
class FakeLocalStore implements LocalStore {
  final Map<String, ClipItem> items = {};
  final Set<String> unsynced = {};
  DateTime? cursor;

  /// Simulates a local clipboard capture.
  void capture(ClipItem item) {
    items[item.id] = item;
    unsynced.add(item.id);
  }

  @override
  Future<List<ClipItem>> pendingOutbox({int limit = 100}) async {
    final out = unsynced.map((id) => items[id]!).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return out.take(limit).toList();
  }

  @override
  Future<void> markSynced(Iterable<String> ids) async =>
      unsynced.removeAll(ids);

  @override
  Future<void> applyRemote(List<ClipItem> incoming) async {
    for (final i in incoming) {
      final existing = items[i.id];
      if (existing == null || !existing.updatedAt.isAfter(i.updatedAt)) {
        items[i.id] = i;
        unsynced.remove(i.id);
      }
    }
  }

  @override
  Future<bool> hasRecentHash(String contentHash, DateTime since) async =>
      items.values.any(
        (i) =>
            !i.isDeleted &&
            i.contentHash == contentHash &&
            i.createdAt.isAfter(since),
      );

  @override
  Future<DateTime?> loadCursor() async => cursor;

  @override
  Future<void> saveCursor(DateTime c) async => cursor = c;
}

int _seq = 0;

/// Builds a text item with deterministic ids.
ClipItem textItem(
  String text, {
  String deviceId = 'dev-a',
  String deviceName = 'A',
  DateTime? at,
}) {
  final now = at ?? DateTime.now().toUtc();
  return ClipItem.create(
    id: 'item-${_seq++}-${now.microsecondsSinceEpoch}',
    deviceId: deviceId,
    deviceName: deviceName,
    type: ClipContentType.text,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: now,
  );
}

/// Device used by tests.
final deviceA = Device(
  id: 'dev-a',
  name: 'A',
  platform: 'test',
  lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);

/// Second device.
final deviceB = Device(
  id: 'dev-b',
  name: 'B',
  platform: 'test',
  lastSeen: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);
