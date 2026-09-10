import 'dart:async';

import 'package:clipsync_core/src/backend/backend_config.dart';
import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/config_field.dart';
import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/model/device.dart';
import 'package:clipsync_core/src/util/redact.dart';
import 'package:supabase/supabase.dart';

/// Supabase (Postgres + PostgREST + Realtime) adapter.
///
/// Schema: two tables `clip_items` and `devices` (names configurable) with
/// row-level security — see `docs/backends/supabase.md`. Talks to the
/// project's public API with the publishable/anon key; optional email +
/// password sign-in scopes rows to that user via RLS.
class SupabaseBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  SupabaseBackend();

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'supabase',
    displayName: 'Supabase',
    description:
        'Hosted or self-hosted Postgres with realtime. Free tier available.',
    docsPath: 'docs/backends/supabase.md',
    supportsRealtime: true,
    supportsBlobs: true,
    configSchema: <ConfigField>[
      ConfigField(
        key: 'url',
        label: 'Project URL',
        kind: ConfigFieldKind.url,
        placeholder: 'https://YOUR_PROJECT.supabase.co',
        help: 'Settings → API → Project URL',
      ),
      ConfigField(
        key: 'anon_key',
        label: 'Publishable (anon) key',
        kind: ConfigFieldKind.secret,
        help:
            'Settings → API → publishable key. Never use the secret/service_role key here.',
      ),
      ConfigField(
        key: 'email',
        label: 'Email (optional)',
        kind: ConfigFieldKind.text,
        required: false,
        help: 'Sign in as a Supabase Auth user so RLS scopes rows to you.',
      ),
      ConfigField(
        key: 'password',
        label: 'Password (optional)',
        kind: ConfigFieldKind.secret,
        required: false,
      ),
      ConfigField(
        key: 'table',
        label: 'Items table',
        kind: ConfigFieldKind.text,
        defaultValue: 'clip_items',
      ),
      ConfigField(
        key: 'devices_table',
        label: 'Devices table',
        kind: ConfigFieldKind.text,
        defaultValue: 'devices',
      ),
      ConfigField(
        key: 'bucket',
        label: 'Storage bucket (optional)',
        kind: ConfigFieldKind.text,
        required: false,
        help:
            'Bucket for large images/files. Leave empty to inline up to 1 MB.',
      ),
    ],
  );

  SupabaseClient? _client;
  late String _table;
  late String _devicesTable;
  String? _email;
  String? _password;
  RealtimeChannel? _channel;
  StreamController<ClipItem>? _watchCtl;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  SupabaseClient get _c =>
      _client ?? (throw BackendException('Supabase not connected'));

  @override
  Future<void> connect(BackendConfig config) async {
    _table = config.stringOr('table', 'clip_items');
    _devicesTable = config.stringOr('devices_table', 'devices');
    _email = config.string('email');
    _password = config.string('password');
    _client = SupabaseClient(config.require('url'), config.require('anon_key'));
  }

  Future<void> _ensureAuth() async {
    final email = _email;
    final password = _password;
    if (email == null || password == null) return;
    if (_c.auth.currentSession != null && !_c.auth.currentSession!.isExpired) {
      return;
    }
    try {
      await _c.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw BackendException(
        'Supabase sign-in failed: ${e.message}',
        cause: e,
        isAuth: true,
      );
    }
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      await _ensureAuth();
      await _c.from(_table).select('id').limit(1);
      return ConnectionCheck.success(
        'Connected to Supabase',
        latency: sw.elapsed,
      );
    } catch (e) {
      return ConnectionCheck.failure(_wrap(e).message);
    }
  }

  /// Columns added after 0.1.0; checked so an old schema fails loudly
  /// instead of silently dropping device management data.
  static const _itemColumns = ['target_device_id'];
  static const _deviceColumns = [
    'status',
    'role',
    'expires_at',
    'paired_by',
    'app_version',
  ];

  @override
  Future<SchemaCheck> verifySchema() async {
    final missing = <String>[];
    for (final (t, cols) in [
      (_table, _itemColumns),
      (_devicesTable, _deviceColumns),
    ]) {
      try {
        await _ensureAuth();
        await _c.from(t).select('id').limit(1);
      } on PostgrestException catch (e) {
        // 42P01 = undefined_table; PGRST205 = table not in schema cache.
        if (e.code == '42P01' || e.code == 'PGRST205' || e.code == '404') {
          missing.add('table $t');
          continue;
        }
        throw _wrap(e);
      }
      for (final col in cols) {
        try {
          await _c.from(t).select(col).limit(1);
        } on PostgrestException catch (e) {
          // 42703 = undefined_column.
          if (e.code == '42703' || e.code == 'PGRST204') {
            missing.add('column $t.$col');
          } else {
            throw _wrap(e);
          }
        }
      }
    }
    return missing.isEmpty
        ? const SchemaCheck.ready()
        : SchemaCheck(
            ok: false,
            missing: missing,
            hint: missing.any((m) => m.startsWith('column'))
                ? 'Run the upgrade SQL in ${descriptorStatic.docsPath}'
                : 'Run the SQL in ${descriptorStatic.docsPath}',
          );
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    if (items.isEmpty) return;
    try {
      await _ensureAuth();
      await _c
          .from(_table)
          .upsert(items.map((i) => i.toMap()).toList(), onConflict: 'id');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    try {
      await _ensureAuth();
      var q = _c.from(_table).select().neq('device_id', excludeDeviceId);
      if (cursor != null) {
        q = q.gt('updated_at', cursor.toUtc().toIso8601String());
      }
      final rows = await q.order('updated_at', ascending: true).limit(limit);
      return rows
          .map((r) => ClipItem.fromMap(Map<String, Object?>.from(r)))
          .toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) {
    final ctl = _watchCtl ??= StreamController<ClipItem>.broadcast(
      onListen: () {
        _channel = _c
            .channel('clipsync:$_table')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: _table,
              callback: (payload) {
                final row = payload.newRecord;
                if (row.isEmpty || row['device_id'] == excludeDeviceId) return;
                try {
                  _watchCtl?.add(
                    ClipItem.fromMap(Map<String, Object?>.from(row)),
                  );
                } catch (e) {
                  _watchCtl?.addError(_wrap(e));
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        final ch = _channel;
        _channel = null;
        if (ch != null) await _c.removeChannel(ch);
      },
    );
    return ctl.stream;
  }

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      await _ensureAuth();
      final ts = now.toUtc().toIso8601String();
      await _c
          .from(_table)
          .update({'deleted_at': ts, 'updated_at': ts, 'content': ''})
          .eq('id', id);
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> registerDevice(Device device) async {
    try {
      await _ensureAuth();
      // PostgREST merges only the columns present in the body, so membership
      // columns keep whatever the managing device wrote (or their defaults
      // on insert).
      await _c
          .from(_devicesTable)
          .upsert(device.presenceMap(), onConflict: 'id');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> updateDevice(Device device) async {
    try {
      await _ensureAuth();
      await _c.from(_devicesTable).upsert(device.toMap(), onConflict: 'id');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteDevice(String id) async {
    try {
      await _ensureAuth();
      await _c.from(_devicesTable).delete().eq('id', id);
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      await _ensureAuth();
      final rows = await _c
          .from(_devicesTable)
          .select()
          .order('last_seen', ascending: false);
      return rows
          .map((r) => Device.fromMap(Map<String, Object?>.from(r)))
          .toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    try {
      await _ensureAuth();
      final rows = await _c
          .from(_table)
          .delete()
          .lt('updated_at', before.toUtc().toIso8601String())
          .select('id');
      return rows.length;
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> dispose() async {
    await _watchCtl?.close();
    _watchCtl = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await _client?.removeChannel(ch);
    await _client?.dispose();
    _client = null;
  }

  BackendException _wrap(Object e) {
    if (e is BackendException) return e;
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final auth =
          code == '401' ||
          code == '403' ||
          code == '42501' ||
          code.startsWith('PGRST30');
      return BackendException(
        redactSecrets(
          'Supabase: ${e.message}${code.isNotEmpty ? ' [$code]' : ''}',
        ),
        cause: e,
        isAuth: auth,
        isTransient: code.startsWith('5') || code == '503',
      );
    }
    if (e is AuthException) {
      return BackendException(
        redactSecrets('Supabase auth: ${e.message}'),
        cause: e,
        isAuth: true,
      );
    }
    return BackendException(
      redactSecrets('Supabase: $e'),
      cause: e,
      isTransient: true,
    );
  }
}
