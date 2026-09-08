import 'package:clipsync_core/clipsync_core.dart' show BackendConfig;
import 'package:clipsync_core/src/backend/backend_config.dart'
    show BackendConfig;
import 'package:meta/meta.dart';

/// Input widget kind for a [ConfigField]; the settings UI maps each to a form
/// control.
enum ConfigFieldKind {
  /// Single-line text.
  text,

  /// Absolute `http(s)://` URL.
  url,

  /// Masked input, stored in the OS credential store.
  secret,

  /// Integer.
  integer,

  /// Boolean toggle.
  boolean,

  /// One of [ConfigField.choices].
  choice,
}

/// One user-editable setting a backend needs.
///
/// Backends declare their whole settings form as a list of these; the app
/// renders the form generically, so adding a database never touches UI code.
@immutable
class ConfigField {
  /// Creates a field definition.
  const ConfigField({
    required this.key,
    required this.label,
    required this.kind,
    this.required = true,
    this.defaultValue,
    this.help,
    this.placeholder,
    this.choices = const <String>[],
    this.validator,
  });

  /// Map key in [BackendConfig.values].
  final String key;

  /// Label shown to the user.
  final String label;

  /// Widget kind.
  final ConfigFieldKind kind;

  /// Whether the field must be non-empty.
  final bool required;

  /// Pre-filled value.
  final Object? defaultValue;

  /// Helper text shown under the control.
  final String? help;

  /// Placeholder text in the control.
  final String? placeholder;

  /// Allowed values when [kind] is [ConfigFieldKind.choice].
  final List<String> choices;

  /// Extra validation; returns an error message or `null`.
  final String? Function(String value)? validator;

  /// Whether the value must be kept in secure storage rather than plain
  /// preferences.
  bool get isSensitive => kind == ConfigFieldKind.secret;

  /// Validates a raw string value, returning an error message or `null`.
  String? validate(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return required ? '$label is required' : null;
    }
    switch (kind) {
      case ConfigFieldKind.url:
        final uri = Uri.tryParse(value);
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
          return '$label must be an absolute URL';
        }
        if (uri.scheme != 'https' && uri.scheme != 'http') {
          return '$label must start with http:// or https://';
        }
        if (uri.userInfo.isNotEmpty) {
          return 'Put credentials in their own fields, not in the URL';
        }
      case ConfigFieldKind.integer:
        if (int.tryParse(value) == null) return '$label must be a whole number';
      case ConfigFieldKind.boolean:
        if (value != 'true' && value != 'false') {
          return '$label must be true or false';
        }
      case ConfigFieldKind.choice:
        if (!choices.contains(value)) {
          return '$label must be one of ${choices.join(', ')}';
        }
      case ConfigFieldKind.text:
      case ConfigFieldKind.secret:
        break;
    }
    return validator?.call(value);
  }
}
