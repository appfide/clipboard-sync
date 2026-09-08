import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Local clipboard history. `synced == false` rows form the outbox.
@DataClassName('ClipRow')
class ClipItems extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text().withDefault(const Constant(''))();
  TextColumn get contentType => text().withDefault(const Constant('text'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get blobRef => text().nullable()();
  TextColumn get contentHash => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  BoolColumn get encrypted => boolean().withDefault(const Constant(false))();
  TextColumn get nonce => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Key/value metadata (sync cursor per backend, schema flags).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Drift database.
@DriftDatabase(tables: [ClipItems, SyncMeta])
class AppDatabase extends _$AppDatabase {
  /// Opens (or creates) the on-disk database.
  AppDatabase() : super(_open());

  /// Wraps an explicit executor (tests use `NativeDatabase.memory()`).
  AppDatabase.withExecutor(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS clip_items_updated_idx ON clip_items (updated_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS clip_items_hash_idx ON clip_items (content_hash)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS clip_items_synced_idx ON clip_items (synced)',
      );
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'clipboard_sync',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );
}
