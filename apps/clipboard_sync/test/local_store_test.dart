import 'package:clipboard_sync/data/local/database.dart';
import 'package:clipboard_sync/data/local/local_store.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ClipItem _item(String text, {String device = 'me', DateTime? at}) {
  final now = at ?? DateTime.now().toUtc();
  return ClipItem.create(
    id: 'id-${now.microsecondsSinceEpoch}-$text',
    deviceId: device,
    deviceName: device,
    type: ClipContentType.text,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: now,
  );
}

void main() {
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = DriftLocalStore(db);
  });
  tearDown(() => db.close());

  test('capture goes to outbox, markSynced clears it', () async {
    expect(await store.capture(_item('a')), isTrue);
    expect(
      await store.capture(_item('a')),
      isFalse,
      reason: 'duplicate at top is ignored',
    );
    final pending = await store.pendingOutbox();
    expect(pending.length, 1);
    await store.markSynced(pending.map((i) => i.id));
    expect(await store.pendingOutbox(), isEmpty);
  });

  test('applyRemote is last-writer-wins and keeps pin', () async {
    final base = DateTime.utc(2026);
    final remote = _item('r', device: 'other', at: base);
    await store.applyRemote([remote]);
    await store.setPinned(remote.id, pinned: true);
    final older = remote.copyWith(
      content: 'stale',
      updatedAt: base.subtract(const Duration(minutes: 1)),
    );
    await store.applyRemote([older]);
    final newer = remote.copyWith(
      content: 'fresh',
      updatedAt: base.add(const Duration(minutes: 1)),
    );
    await store.applyRemote([newer]);
    final rows = await store.watchHistory().first;
    expect(rows.single.item.content, 'fresh');
    expect(rows.single.pinned, isTrue);
    expect(rows.single.synced, isTrue);
  });

  test('cursor round-trips with millisecond precision', () async {
    expect(await store.loadCursor(), isNull);
    final c = DateTime.utc(2026, 9, 8, 12, 0, 0, 123);
    await store.saveCursor(c);
    expect(await store.loadCursor(), c);
    await store.resetCursor();
    expect(await store.loadCursor(), isNull);
  });

  test('hasRecentHash respects window and tombstones', () async {
    final i = _item('echo');
    await store.capture(i);
    expect(
      await store.hasRecentHash(
        i.contentHash,
        DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
      ),
      isTrue,
    );
    expect(
      await store.hasRecentHash(
        i.contentHash,
        DateTime.now().toUtc().add(const Duration(seconds: 5)),
      ),
      isFalse,
    );
    await store.delete(i.id, DateTime.now().toUtc());
    expect(
      await store.hasRecentHash(i.contentHash, DateTime.utc(2000)),
      isFalse,
    );
    expect((await store.pendingOutbox()).single.isDeleted, isTrue);
  });

  test('search filters by content and hides deleted', () async {
    await store.capture(_item('hello world'));
    await store.capture(_item('goodbye'));
    expect((await store.watchHistory(query: 'hello').first).length, 1);
    expect((await store.watchHistory().first).length, 2);
  });

  test('purgeBefore keeps pinned and unsynced rows', () async {
    final old = _item('old', at: DateTime.utc(2000));
    final pinnedOld = _item('pinned', at: DateTime.utc(2000));
    await store.applyRemote([old, pinnedOld]);
    await store.setPinned(pinnedOld.id, pinned: true);
    await store.capture(_item('unsynced', at: DateTime.utc(2000)));
    final n = await store.purgeBefore(DateTime.utc(2001));
    expect(n, 1);
  });
}
