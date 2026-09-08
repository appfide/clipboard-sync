import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/backends/couchdb/couchdb_backend.dart';
import 'package:clipsync_core/src/backends/firestore/firestore_backend.dart';
import 'package:clipsync_core/src/backends/memory/memory_backend.dart';
import 'package:clipsync_core/src/backends/mongodb/mongodb_backend.dart';
import 'package:clipsync_core/src/backends/pocketbase/pocketbase_backend.dart';
import 'package:clipsync_core/src/backends/supabase/supabase_backend.dart';

/// Factory producing a fresh, unconnected [SyncBackend].
typedef BackendFactory = SyncBackend Function();

/// Registry of every backend the app can use, keyed by
/// [BackendDescriptor.id].
///
/// The app builds its backend picker from [descriptors] and instantiates the
/// chosen one with [create]. Tests register fakes with [register].
class BackendRegistry {
  /// Creates a registry pre-populated with every built-in backend.
  BackendRegistry.builtIn() {
    register(SupabaseBackend.descriptorStatic, SupabaseBackend.new);
    register(PocketBaseBackend.descriptorStatic, PocketBaseBackend.new);
    register(CouchDbBackend.descriptorStatic, CouchDbBackend.new);
    register(FirestoreBackend.descriptorStatic, FirestoreBackend.new);
    register(MongoDbBackend.descriptorStatic, MongoDbBackend.new);
    register(MemoryBackend.descriptorStatic, MemoryBackend.new);
  }

  /// Creates an empty registry.
  BackendRegistry.empty();

  final Map<String, (BackendDescriptor, BackendFactory)> _entries = {};

  /// Registers or replaces a backend.
  void register(BackendDescriptor descriptor, BackendFactory factory) {
    _entries[descriptor.id] = (descriptor, factory);
  }

  /// All descriptors in registration order.
  List<BackendDescriptor> get descriptors =>
      _entries.values.map((e) => e.$1).toList(growable: false);

  /// Descriptor for [id], or `null`.
  BackendDescriptor? descriptor(String id) => _entries[id]?.$1;

  /// Instantiates the backend registered under [id].
  ///
  /// Throws [ArgumentError] for unknown ids.
  SyncBackend create(String id) {
    final entry = _entries[id];
    if (entry == null) throw ArgumentError.value(id, 'id', 'Unknown backend');
    return entry.$2();
  }
}
