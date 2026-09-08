import 'package:clipboard_sync/features/settings/backend_form.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pick a database, fill its form, test, verify schema, save.
/// Used both by onboarding and from Settings.
class BackendSetupPage extends ConsumerStatefulWidget {
  /// Creates the page. [onboarding] hides the back button and marks
  /// onboarding done on save.
  const BackendSetupPage({this.onboarding = false, super.key});

  /// Wizard mode.
  final bool onboarding;

  @override
  ConsumerState<BackendSetupPage> createState() => _BackendSetupPageState();
}

class _BackendSetupPageState extends ConsumerState<BackendSetupPage> {
  final _formKey = GlobalKey<BackendFormState>();
  late String _backendId;
  Map<String, String> _values = {};
  ConnectionCheck? _conn;
  SchemaCheck? _schema;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backendId = s.backendId;
    _values = Map.of(s.backendValues);
  }

  Future<void> _switchBackend(String id) async {
    final values = await ref
        .read(settingsRepositoryProvider)
        .loadBackendValues(id);
    setState(() {
      _backendId = id;
      _values = values;
      _conn = null;
      _schema = null;
    });
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() {
      _busy = true;
      _conn = null;
      _schema = null;
    });
    final (c, s) = await ref
        .read(syncControllerProvider.notifier)
        .probe(BackendConfig(backendId: _backendId, values: _values));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _conn = c;
      _schema = s;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final notifier = ref.read(settingsProvider.notifier);
    final previous = ref.read(settingsProvider).backendId;
    if (previous != _backendId) {
      await ref.read(localStoreProvider).resetCursor();
    }
    await notifier.update(
      (s) => s.copyWith(
        backendId: _backendId,
        backendValues: _values,
        onboarded: true,
      ),
    );
    if (!mounted) return;
    if (widget.onboarding) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(backendRegistryProvider);
    final descriptor = registry.descriptor(_backendId)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.onboarding ? 'Choose where to sync' : 'Sync backend',
        ),
        automaticallyImplyLeading: !widget.onboarding,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('backend-picker'),
            initialValue: _backendId,
            decoration: const InputDecoration(labelText: 'Database'),
            items: [
              for (final d in registry.descriptors)
                DropdownMenuItem(value: d.id, child: Text(d.displayName)),
            ],
            onChanged: _busy
                ? null
                : (id) => id == null ? null : _switchBackend(id),
          ),
          const SizedBox(height: 8),
          Text(descriptor.description, style: theme.textTheme.bodyMedium),
          Wrap(
            spacing: 8,
            children: [
              if (descriptor.supportsRealtime)
                const Chip(
                  label: Text('Realtime'),
                  visualDensity: VisualDensity.compact,
                ),
              if (!descriptor.supportsRealtime && descriptor.id != 'memory')
                const Chip(
                  label: Text('Polling'),
                  visualDensity: VisualDensity.compact,
                ),
              if (descriptor.supportsBlobs)
                const Chip(
                  label: Text('Large files'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (descriptor.id != 'memory')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Setup guide & schema'),
                onPressed: () => launchUrl(
                  Uri.parse(descriptor.docsUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          const Divider(height: 24),
          BackendForm(
            key: ValueKey('form-$_backendId'),
            descriptor: descriptor,
            initialValues: _values,
            onChanged: (v) => _values = v,
          ),
          if (_formKey.currentState == null) const SizedBox.shrink(),
          if (descriptor.configSchema.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('test-connection'),
                    onPressed: _busy ? null : _test,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Test connection & schema'),
                  ),
                ),
              ],
            ),
            if (_conn != null)
              _ResultTile(
                ok: _conn!.ok,
                title: _conn!.ok ? 'Connected' : 'Connection failed',
                detail:
                    '${_conn!.message}${_conn!.latency != null ? ' · ${_conn!.latency!.inMilliseconds} ms' : ''}',
              ),
            if (_schema != null)
              _ResultTile(
                ok: _schema!.ok,
                title: _schema!.ok ? 'Schema ready' : 'Schema incomplete',
                detail: _schema!.ok
                    ? 'All tables/collections found.'
                    : 'Missing: ${_schema!.missing.join(', ')}\n${_schema!.hint ?? ''}',
              ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('save-backend'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(widget.onboarding ? 'Start syncing' : 'Save'),
          ),
          if (widget.onboarding)
            TextButton(
              onPressed: () async {
                await ref
                    .read(settingsProvider.notifier)
                    .update(
                      (s) => s.copyWith(
                        backendId: 'memory',
                        backendValues: const {},
                        onboarded: true,
                      ),
                    );
                if (context.mounted) context.go('/');
              },
              child: const Text('Skip — keep history on this device only'),
            ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.ok,
    required this.title,
    required this.detail,
  });
  final bool ok;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.error,
        color: ok ? scheme.primary : scheme.error,
      ),
      title: Text(title),
      subtitle: SelectableText(detail),
    );
  }
}
