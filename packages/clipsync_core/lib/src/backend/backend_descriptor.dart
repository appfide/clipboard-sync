import 'package:clipsync_core/src/backend/config_field.dart';
import 'package:meta/meta.dart';

/// Static description of a backend: identity, capabilities and the settings
/// form it needs. Everything the UI shows about a backend comes from here.
@immutable
class BackendDescriptor {
  /// Creates a descriptor.
  const BackendDescriptor({
    required this.id,
    required this.displayName,
    required this.description,
    required this.docsPath,
    required this.configSchema,
    this.supportsRealtime = false,
    this.supportsBlobs = false,
    this.maxInlineBytes = 1024 * 1024,
  });

  /// Stable identifier persisted in settings (`supabase`, `couchdb`, ...).
  final String id;

  /// Name shown in the backend picker.
  final String displayName;

  /// One-line summary shown in the picker.
  final String description;

  /// Path of the setup guide inside the repo, e.g. `docs/backends/supabase.md`.
  final String docsPath;

  /// Settings form definition.
  final List<ConfigField> configSchema;

  /// Whether `watch()` pushes changes live (otherwise the engine polls).
  final bool supportsRealtime;

  /// Whether large binaries can be stored out-of-row (storage bucket, file
  /// field, attachment). When false, binaries above [maxInlineBytes] are
  /// skipped.
  final bool supportsBlobs;

  /// Largest payload inlined as base64 in the document.
  final int maxInlineBytes;

  /// Absolute URL of the setup guide on GitHub.
  String get docsUrl =>
      'https://github.com/appfide/clipboard-sync/blob/main/$docsPath';

  /// Field keys that must be stored in secure storage.
  Iterable<String> get secretKeys =>
      configSchema.where((f) => f.isSensitive).map((f) => f.key);
}
