import 'package:clipboard_sync/features/settings/backend_form.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
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
  bool _secure = true;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backendId = s.backendId;
    _values = Map.of(s.backendValues);
  }

  Future<void> _switchBackend(String id) async {
    if (id == _backendId) return;
    final values = await ref
        .read(settingsRepositoryProvider)
        .loadBackendValues(id);
    if (!mounted) return;
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
    setState(() => _busy = true);
    await notifier.update(
      (s) => s.copyWith(
        backendId: _backendId,
        backendValues: _values,
        onboarded: true,
      ),
    );
    if (_secure && _backendId != 'memory') {
      try {
        await ref.read(syncControllerProvider.notifier).secureNewGroup();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Saved, but the group could not be secured yet: ${redactSecrets('$e')}. Use Settings → Devices → Secure this group once connected.',
                ),
              ),
            );
        }
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
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
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Choose where to sync' : 'Database'),
        automaticallyImplyLeading: !widget.onboarding,
        leading: widget.onboarding
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/onboarding'),
              )
            : null,
      ),
      body: ContentColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text('Pick a database', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'The app connects to it directly — no server in between.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 560 ? 3 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: cols == 3 ? 2.0 : 1.7,
                  children: [
                    for (final d in registry.descriptors)
                      _BackendTile(
                        key: ValueKey('backend-${d.id}'),
                        descriptor: d,
                        selected: d.id == _backendId,
                        onTap: _busy ? null : () => _switchBackend(d.id),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    descriptor.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (descriptor.id != 'memory')
                  TextButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Setup guide'),
                    onPressed: () => launchUrl(
                      Uri.parse(descriptor.docsUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
              ],
            ),
            Text(descriptor.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: BackendForm(
                  key: ValueKey('form-$_backendId'),
                  descriptor: descriptor,
                  initialValues: _values,
                  onChanged: (v) => _values = v,
                ),
              ),
            ),
            if (descriptor.configSchema.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('test-connection'),
                onPressed: _busy ? null : _test,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded, size: 18),
                label: Text(_busy ? 'Testing…' : 'Test connection & schema'),
              ),
              if (_conn != null) ...[
                const SizedBox(height: 12),
                _Result(
                  ok: _conn!.ok,
                  title: _conn!.ok ? 'Connected' : 'Connection failed',
                  detail:
                      '${_conn!.message}${_conn!.latency != null ? ' · ${_conn!.latency!.inMilliseconds} ms' : ''}',
                ),
              ],
              if (_schema != null) ...[
                const SizedBox(height: 8),
                _Result(
                  ok: _schema!.ok,
                  title: _schema!.ok ? 'Schema ready' : 'Schema incomplete',
                  detail: _schema!.ok
                      ? 'All tables and collections found.'
                      : 'Missing: ${_schema!.missing.join(', ')}\n${_schema!.hint ?? ''}',
                ),
              ],
            ],
            if (descriptor.id != 'memory') ...[
              const SizedBox(height: 12),
              Card(
                child: SwitchRow(
                  key: const ValueKey('secure-new-group'),
                  icon: Icons.verified_user_rounded,
                  title: 'Encrypt and sign this group',
                  subtitle: _secure
                      ? 'Recommended. A random passphrase is generated and this device becomes the admin; other devices receive the key through pairing. Turn off only to join a group by typing a passphrase.'
                      : 'Off — clips are stored readable by the database and anyone with its credentials can pose as a device.',
                  value: _secure,
                  onChanged: (v) => setState(() => _secure = v),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('save-backend'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(widget.onboarding ? 'Start syncing' : 'Save'),
            ),
            if (widget.onboarding)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
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
                  child: Text(
                    'Skip — keep history on this device only',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackendTile extends StatefulWidget {
  const _BackendTile({
    required this.descriptor,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final BackendDescriptor descriptor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_BackendTile> createState() => _BackendTileState();
}

class _BackendTileState extends State<_BackendTile> {
  bool _hover = false;

  static IconData _iconFor(String id) => switch (id) {
    'supabase' => Icons.bolt_rounded,
    'pocketbase' => Icons.inventory_2_outlined,
    'couchdb' => Icons.weekend_outlined,
    'firestore' => Icons.local_fire_department_outlined,
    'mongodb' => Icons.eco_outlined,
    _ => Icons.phonelink_lock_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final d = widget.descriptor;
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        selected: sel,
        button: true,
        label: d.displayName,
        child: AnimatedContainer(
          duration: AppTokens.fast,
          decoration: BoxDecoration(
            color: sel
                ? scheme.primary.withValues(alpha: 0.08)
                : (_hover ? scheme.surfaceContainer : c.surfaceRaised),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: sel ? scheme.primary : c.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LeadingIcon(
                          icon: _iconFor(d.id),
                          color: sel ? scheme.primary : c.muted,
                          size: 32,
                        ),
                        const Spacer(),
                        if (sel)
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      d.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.id == 'memory'
                          ? 'No sync'
                          : (d.supportsRealtime ? 'Realtime' : 'Polling'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: d.supportsRealtime && d.id != 'memory'
                            ? c.success
                            : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.ok, required this.title, required this.detail});
  final bool ok;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final color = ok ? c.success : scheme.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
