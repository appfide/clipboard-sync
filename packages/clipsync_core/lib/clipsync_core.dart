/// Pure-Dart core for Clipboard Sync: domain model, pluggable database
/// backends, optional end-to-end encryption and the sync engine.
///
/// This library has no Flutter dependency so it can be unit-tested with
/// `dart test` and reused by CLI tools.
library;

export 'src/backend/backend_config.dart';
export 'src/backend/backend_descriptor.dart';
export 'src/backend/backend_registry.dart';
export 'src/backend/config_field.dart';
export 'src/backend/sync_backend.dart';
export 'src/backends/couchdb/couchdb_backend.dart';
export 'src/backends/firestore/firestore_backend.dart';
export 'src/backends/memory/memory_backend.dart';
export 'src/backends/mongodb/mongodb_backend.dart';
export 'src/backends/pocketbase/pocketbase_backend.dart';
export 'src/backends/supabase/supabase_backend.dart';
export 'src/crypto/clip_cipher.dart';
export 'src/model/clip_content_type.dart';
export 'src/model/clip_item.dart';
export 'src/model/device.dart';
export 'src/pairing/pairing_payload.dart';
export 'src/sync/local_store.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_status.dart';
export 'src/util/hashing.dart';
export 'src/util/redact.dart';
