import 'dart:async';
import 'dart:convert';

import 'package:clipsync_core/src/backend/backend_config.dart';
import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/config_field.dart';
import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/model/device.dart';
import 'package:clipsync_core/src/util/http_errors.dart';
import 'package:dio/dio.dart';

/// Apache CouchDB / IBM Cloudant adapter over the plain HTTP API.
///
/// One database holds both item docs (`_id = "clip:<uuid>"`) and device docs
/// (`_id = "device:<uuid>"`), discriminated by a `kind` field. Pull uses a
/// Mango `_find` on `updated_at`; realtime uses the `_changes` longpoll feed.
/// Required index is documented in `docs/backends/couchdb.md`.
class CouchDbBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  CouchDbBackend({Dio? dio}) : _injectedDio = dio;

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'couchdb',
    displayName: 'CouchDB / Cloudant',
    description:
        'Self-hosted CouchDB or IBM Cloudant. Uses the HTTP API directly.',
    docsPath: 'docs/backends/couchdb.md',
    supportsRealtime: true,
    supportsBlobs: true,
    configSchema: <ConfigField>[
      ConfigField(
        key: 'url',
        label: 'Server URL',
        kind: ConfigFieldKind.url,
        placeholder: 'https://couch.example.com:5984',
      ),
      ConfigField(
        key: 'database',
        label: 'Database name',
        kind: ConfigFieldKind.text,
        defaultValue: 'clipboard_sync',
      ),
      ConfigField(
        key: 'username',
        label: 'Username',
        kind: ConfigFieldKind.text,
      ),
      ConfigField(
        key: 'password',
        label: 'Password',
        kind: ConfigFieldKind.secret,
      ),
    ],
  );

  final Dio? _injectedDio;
  Dio? _dio;
  late String _db;
  StreamController<ClipItem>? _watchCtl;
  bool _watching = false;

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  Dio get _d => _dio ?? (throw BackendException('CouchDB not connected'));

  @override
  Future<void> connect(BackendConfig config) async {
    _db = Uri.encodeComponent(config.stringOr('database', 'clipboard_sync'));
    final auth = base64Encode(
      utf8.encode(
        '${config.require('username')}:${config.require('password')}',
      ),
    );
    _dio =
        _injectedDio ??
        newDio(
          baseUrl: config.url('url'),
          headers: {
            'Authorization': 'Basic $auth',
            'Accept': 'application/json',
          },
        );
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      final r = await _d.get<Map<String, dynamic>>('/');
      await _d.get<Map<String, dynamic>>('/_session');
      final v = r.data?['version'] ?? '?';
      return ConnectionCheck.success('CouchDB $v', latency: sw.elapsed);
    } catch (e) {
      return ConnectionCheck.failure(
        toBackendException(e, context: 'CouchDB').message,
      );
    }
  }

  @override
  Future<SchemaCheck> verifySchema() async {
    try {
      final missing = <String>[];
      try {
        await _d.get<Map<String, dynamic>>('/$_db');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          return SchemaCheck(
            ok: false,
            missing: ['database $_db'],
            hint:
                'Create the database and index per ${descriptorStatic.docsPath}',
          );
        }
        rethrow;
      }
      final idx = await _d.get<Map<String, dynamic>>('/$_db/_index');
      final indexes = (idx.data?['indexes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final hasUpdated = indexes.any(
        (i) => jsonEncode(i['def']).contains('updated_at'),
      );
      if (!hasUpdated) missing.add('index on kind+updated_at');
      return missing.isEmpty
          ? const SchemaCheck.ready()
          : SchemaCheck(
              ok: false,
              missing: missing,
              hint: 'Create the Mango index per ${descriptorStatic.docsPath}',
            );
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB');
    }
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    if (items.isEmpty) return;
    try {
      final ids = items.map((i) => 'clip:${i.id}').toList();
      final revs = await _fetchRevs(ids);
      final docs = [
        for (final i in items)
          <String, Object?>{
            '_id': 'clip:${i.id}',
            if (revs['clip:${i.id}'] != null) '_rev': revs['clip:${i.id}'],
            'kind': 'clip',
            ...i.toMap(),
          },
      ];
      final r = await _d.post<List<dynamic>>(
        '/$_db/_bulk_docs',
        data: {'docs': docs},
      );
      final conflicts = (r.data ?? const [])
          .cast<Map<String, dynamic>>()
          .where((x) => x['error'] != null)
          .toList();
      if (conflicts.isNotEmpty) {
        throw BackendException(
          'CouchDB rejected ${conflicts.length} doc(s): ${conflicts.first['reason']}',
          isTransient: true,
        );
      }
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB upsert');
    }
  }

  Future<Map<String, String?>> _fetchRevs(List<String> ids) async {
    final r = await _d.post<Map<String, dynamic>>(
      '/$_db/_all_docs',
      data: {'keys': ids},
    );
    final out = <String, String?>{};
    for (final row
        in (r.data?['rows'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()) {
      final value = row['value'];
      if (value is Map && value['deleted'] != true) {
        out[row['key'] as String] = value['rev'] as String?;
      }
    }
    return out;
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    try {
      final selector = <String, Object?>{
        'kind': 'clip',
        'device_id': {r'$ne': excludeDeviceId},
        'updated_at': {r'$gt': cursor?.toUtc().toIso8601String() ?? ''},
      };
      final r = await _d.post<Map<String, dynamic>>(
        '/$_db/_find',
        data: {
          'selector': selector,
          'sort': [
            {'kind': 'asc'},
            {'updated_at': 'asc'},
          ],
          'limit': limit,
        },
      );
      final docs = (r.data?['docs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      return docs.map(_toItem).toList();
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB pull');
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) {
    final ctl = _watchCtl ??= StreamController<ClipItem>.broadcast(
      onListen: () {
        _watching = true;
        unawaited(_longpoll(excludeDeviceId));
      },
      onCancel: () => _watching = false,
    );
    return ctl.stream;
  }

  Future<void> _longpoll(String excludeDeviceId) async {
    var since = 'now';
    while (_watching && _dio != null) {
      try {
        final r = await _d.post<Map<String, dynamic>>(
          '/$_db/_changes',
          queryParameters: {
            'feed': 'longpoll',
            'since': since,
            'include_docs': 'true',
            'filter': '_selector',
            'timeout': '55000',
          },
          data: {
            'selector': {
              'kind': 'clip',
              'device_id': {r'$ne': excludeDeviceId},
            },
          },
          options: Options(receiveTimeout: const Duration(seconds: 70)),
        );
        since = (r.data?['last_seq'] ?? since).toString();
        for (final row
            in (r.data?['results'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>()) {
          final doc = row['doc'];
          if (doc is Map<String, dynamic>) _watchCtl?.add(_toItem(doc));
        }
      } catch (e) {
        if (!_watching) return;
        _watchCtl?.addError(toBackendException(e, context: 'CouchDB changes'));
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      final r = await _d.get<Map<String, dynamic>>(
        '/$_db/clip:$id',
        options: Options(validateStatus: (s) => s == 200 || s == 404),
      );
      if (r.statusCode == 404) return;
      final ts = now.toUtc().toIso8601String();
      final doc = Map<String, Object?>.from(r.data!)
        ..['deleted_at'] = ts
        ..['updated_at'] = ts
        ..['content'] = '';
      await _d.put<Map<String, dynamic>>('/$_db/clip:$id', data: doc);
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB tombstone');
    }
  }

  @override
  Future<void> registerDevice(Device device) async {
    try {
      final id = 'device:${device.id}';
      final revs = await _fetchRevs([id]);
      await _d.put<Map<String, dynamic>>(
        '/$_db/$id',
        data: {
          '_id': id,
          if (revs[id] != null) '_rev': revs[id],
          'kind': 'device',
          ...device.toMap(),
        },
      );
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB device');
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      final r = await _d.post<Map<String, dynamic>>(
        '/$_db/_find',
        data: {
          'selector': {'kind': 'device'},
          'limit': 200,
        },
      );
      final docs = (r.data?['docs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      return docs
          .map((d) => Device.fromMap(Map<String, Object?>.from(d)))
          .toList();
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB devices');
    }
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    try {
      final r = await _d.post<Map<String, dynamic>>(
        '/$_db/_find',
        data: {
          'selector': {
            'kind': 'clip',
            'updated_at': {r'$lt': before.toUtc().toIso8601String()},
          },
          'fields': ['_id', '_rev'],
          'limit': 1000,
        },
      );
      final docs = (r.data?['docs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (docs.isEmpty) return 0;
      await _d.post<List<dynamic>>(
        '/$_db/_bulk_docs',
        data: {
          'docs': [
            for (final d in docs)
              {'_id': d['_id'], '_rev': d['_rev'], '_deleted': true},
          ],
        },
      );
      return docs.length;
    } catch (e) {
      throw toBackendException(e, context: 'CouchDB purge');
    }
  }

  @override
  Future<void> dispose() async {
    _watching = false;
    await _watchCtl?.close();
    _watchCtl = null;
    if (_injectedDio == null) _dio?.close(force: true);
    _dio = null;
  }

  static ClipItem _toItem(Map<String, dynamic> doc) =>
      ClipItem.fromMap(Map<String, Object?>.from(doc));
}
