import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';

/// Renders a backend's settings form from its [BackendDescriptor.configSchema].
///
/// Adding a database never touches this widget — every field, label, help
/// text and validation rule comes from the descriptor.
class BackendForm extends StatefulWidget {
  /// Creates the form.
  const BackendForm({
    required this.descriptor,
    required this.initialValues,
    required this.onChanged,
    super.key,
  });

  /// Backend being configured.
  final BackendDescriptor descriptor;

  /// Values to pre-fill.
  final Map<String, String> initialValues;

  /// Called with the full value map on every edit.
  final void Function(Map<String, String> values) onChanged;

  @override
  State<BackendForm> createState() => BackendFormState();
}

/// Public state so parents can trigger validation.
class BackendFormState extends State<BackendForm> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, String> _values;
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _values = {
      for (final f in widget.descriptor.configSchema)
        if (widget.initialValues[f.key] != null)
          f.key: widget.initialValues[f.key]!
        else if (f.defaultValue != null)
          f.key: f.defaultValue.toString(),
    };
  }

  /// Runs validators; returns true when every field is valid.
  bool validate() => _formKey.currentState?.validate() ?? false;

  /// Current values.
  Map<String, String> get values => Map.unmodifiable(_values);

  void _set(String key, String value) {
    setState(() => _values[key] = value);
    widget.onChanged(values);
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.descriptor.configSchema;
    if (fields.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Nothing to configure.'),
      );
    }
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _field(f),
            ),
        ],
      ),
    );
  }

  Widget _field(ConfigField f) {
    switch (f.kind) {
      case ConfigFieldKind.boolean:
        return SwitchListTile(
          key: ValueKey('field-${f.key}'),
          title: Text(f.label),
          subtitle: f.help == null ? null : Text(f.help!),
          value: _values[f.key] == 'true',
          onChanged: (v) => _set(f.key, v.toString()),
        );
      case ConfigFieldKind.choice:
        return DropdownButtonFormField<String>(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key],
          decoration: InputDecoration(labelText: f.label, helperText: f.help),
          items: [
            for (final c in f.choices)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          validator: f.validate,
          onChanged: (v) => _set(f.key, v ?? ''),
        );
      case ConfigFieldKind.secret:
        final shown = _revealed.contains(f.key);
        return TextFormField(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key],
          obscureText: !shown,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: f.label,
            helperText: f.help,
            helperMaxLines: 3,
            hintText: f.placeholder,
            suffixIcon: IconButton(
              icon: Icon(shown ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(
                () => shown ? _revealed.remove(f.key) : _revealed.add(f.key),
              ),
            ),
          ),
          validator: f.validate,
          onChanged: (v) => _set(f.key, v),
        );
      case ConfigFieldKind.url:
      case ConfigFieldKind.text:
      case ConfigFieldKind.integer:
        return TextFormField(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key],
          keyboardType: switch (f.kind) {
            ConfigFieldKind.url => TextInputType.url,
            ConfigFieldKind.integer => TextInputType.number,
            _ => TextInputType.text,
          },
          autocorrect: false,
          decoration: InputDecoration(
            labelText: f.label,
            helperText: f.help,
            helperMaxLines: 3,
            hintText: f.placeholder,
          ),
          validator: f.validate,
          onChanged: (v) => _set(f.key, v),
        );
    }
  }
}
