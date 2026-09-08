import 'package:clipsync_core/clipsync_core.dart' show SyncEngine;
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/sync/sync_engine.dart' show SyncEngine;

/// Local persistence the [SyncEngine] drives. The app implements this with
/// drift/SQLite; tests use an in-memory version.
///
/// Items live in one table; the *outbox* is the subset with
/// `synced == false`. The engine never deletes rows — retention does.
abstract class LocalStore {
  /// Items captured locally that have not been pushed yet, oldest first.
  Future<List<ClipItem>> pendingOutbox({int limit = 100});

  /// Marks [ids] as pushed.
  Future<void> markSynced(Iterable<String> ids);

  /// Applies items received from the backend. Must be last-writer-wins on
  /// `updated_at` and must set `synced = true` for these rows.
  Future<void> applyRemote(List<ClipItem> items);

  /// Whether a live (non-deleted) item with [contentHash] exists that was
  /// created after [since]. Used to suppress echo loops.
  Future<bool> hasRecentHash(String contentHash, DateTime since);

  /// Last remote `updated_at` fully applied, or `null` on first sync.
  Future<DateTime?> loadCursor();

  /// Persists the cursor.
  Future<void> saveCursor(DateTime cursor);
}
