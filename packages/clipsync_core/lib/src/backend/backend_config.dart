import 'package:clipsync_core/clipsync_core.dart' show ConfigField;
import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/config_field.dart' show ConfigField;
import 'package:meta/meta.dart';

/// Values the user entered for one backend, keyed by [ConfigField.key].
///
/// Values are kept as strings exactly as typed; typed accessors parse on read
/// so the app can persist the whole thing as `Map<String, String>` (secret
/// fields go to secure storage, the rest to plain preferences).
@immutable
class BackendConfig {
  /// Creates a config for [backendId].
  const BackendConfig({required this.backendId, required this.values});

  /// Empty config for [backendId].
  const BackendConfig.empty(this.backendId) : values = const {};

  /// [BackendDescriptor.id] this config belongs to.
  final String backendId;

  /// Raw values keyed by field key.
  final Map<String, String> values;

  /// Trimmed string value, or `null` when absent/empty.
  String? string(String key) {
    final v = values[key]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// String value or [fallback].
  String stringOr(String key, String fallback) => string(key) ?? fallback;

  /// Required string; throws [StateError] when missing.
  String require(String key) =>
      string(key) ?? (throw StateError('Missing required setting "$key"'));

  /// Integer value or [fallback].
  int intOr(String key, int fallback) =>
      int.tryParse(string(key) ?? '') ?? fallback;

  /// Boolean value or [fallback].
  bool boolOr(String key, {required bool fallback}) =>
      switch (string(key)?.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => fallback,
      };

  /// URL with any trailing slash removed.
  String? url(String key) {
    final v = string(key);
    if (v == null) return null;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  /// Copy with [key] set to [value].
  BackendConfig set(String key, String value) => BackendConfig(
    backendId: backendId,
    values: <String, String>{...values, key: value},
  );

  /// Validates against [descriptor], returning `{fieldKey: error}`.
  Map<String, String> validate(BackendDescriptor descriptor) {
    final errors = <String, String>{};
    for (final field in descriptor.configSchema) {
      final err = field.validate(values[field.key]);
      if (err != null) errors[field.key] = err;
    }
    return errors;
  }

  @override
  bool operator ==(Object other) =>
      other is BackendConfig &&
      other.backendId == backendId &&
      _mapEquals(other.values, values);

  @override
  int get hashCode => Object.hash(
    backendId,
    Object.hashAllUnordered(
      values.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
