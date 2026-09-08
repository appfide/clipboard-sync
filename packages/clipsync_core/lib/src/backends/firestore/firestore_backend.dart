import 'dart:async';

import 'package:clipsync_core/src/backend/backend_config.dart';
import 'package:clipsync_core/src/backend/backend_descriptor.dart';
import 'package:clipsync_core/src/backend/config_field.dart';
import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:clipsync_core/src/model/device.dart';
import 'package:clipsync_core/src/util/http_errors.dart';
import 'package:dio/dio.dart';

/// Cloud Firestore adapter over the REST API (`firestore.googleapis.com`).
///
/// The official `cloud_firestore` plugin does not support Linux, so this
/// adapter uses REST on every platform. Auth uses Firebase Identity Toolkit:
/// email + password when provided, otherwise anonymous sign-in. Security
/// rules in `docs/backends/firestore.md` restrict access accordingly.
///
/// Polling only — the REST `Listen` endpoint requires gRPC streaming.
class FirestoreBackend implements SyncBackend {
  /// Creates an unconnected adapter.
  FirestoreBackend({Dio? dio, Dio? authDio})
    : _injectedDio = dio,
      _injectedAuthDio = authDio;

  /// Descriptor shared with the registry.
  static const BackendDescriptor descriptorStatic = BackendDescriptor(
    id: 'firestore',
    displayName: 'Firebase Firestore',
    description: 'Google Cloud Firestore via REST. Free Spark tier available.',
    docsPath: 'docs/backends/firestore.md',
    configSchema: <ConfigField>[
      ConfigField(
        key: 'project_id',
        label: 'Project ID',
        kind: ConfigFieldKind.text,
        placeholder: 'my-project-123ab',
        help: 'Firebase console → Project settings → Project ID',
      ),
      ConfigField(
        key: 'api_key',
        label: 'Web API key',
        kind: ConfigFieldKind.secret,
        help: 'Project settings → General → Web API Key',
      ),
      ConfigField(
        key: 'email',
        label: 'Email (optional)',
        kind: ConfigFieldKind.text,
        required: false,
        help: 'Firebase Auth email/password user. Empty = anonymous sign-in.',
      ),
      ConfigField(
        key: 'password',
        label: 'Password (optional)',
        kind: ConfigFieldKind.secret,
        required: false,
      ),
      ConfigField(
        key: 'collection',
        label: 'Items collection',
        kind: ConfigFieldKind.text,
        defaultValue: 'clip_items',
      ),
      ConfigField(
        key: 'devices_collection',
        label: 'Devices collection',
        kind: ConfigFieldKind.text,
        defaultValue: 'devices',
      ),
    ],
  );

  static const _firestoreHost = 'https://firestore.googleapis.com';
  static const _identityHost = 'https://identitytoolkit.googleapis.com';
  static const _tokenHost = 'https://securetoken.googleapis.com';

  final Dio? _injectedDio;
  final Dio? _injectedAuthDio;
  Dio? _dio;
  Dio? _auth;
  late String _project;
  late String _apiKey;
  late String _collection;
  late String _devicesCollection;
  String? _email;
  String? _password;
  String? _idToken;
  String? _refreshToken;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  BackendDescriptor get descriptor => descriptorStatic;

  String get _docsBase =>
      '/v1/projects/$_project/databases/(default)/documents';

  @override
  Future<void> connect(BackendConfig config) async {
    _project = config.require('project_id');
    _apiKey = config.require('api_key');
    _collection = config.stringOr('collection', 'clip_items');
    _devicesCollection = config.stringOr('devices_collection', 'devices');
    _email = config.string('email');
    _password = config.string('password');
    _dio = _injectedDio ?? newDio(baseUrl: _firestoreHost);
    _auth = _injectedAuthDio ?? newDio();
    _idToken = null;
  }

  Future<Options> _opts() async {
    final now = DateTime.now().toUtc();
    if (_idToken == null ||
        now.isAfter(_tokenExpiry.subtract(const Duration(minutes: 2)))) {
      await _signIn();
    }
    return Options(headers: {'Authorization': 'Bearer $_idToken'});
  }

  Future<void> _signIn() async {
    final auth = _auth ?? (throw BackendException('Firestore not connected'));
    try {
      Map<String, dynamic> data;
      if (_refreshToken != null) {
        final r = await auth.post<Map<String, dynamic>>(
          '$_tokenHost/v1/token',
          queryParameters: {'key': _apiKey},
          data: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        data = {
          'idToken': r.data!['id_token'],
          'refreshToken': r.data!['refresh_token'],
          'expiresIn': r.data!['expires_in'],
        };
      } else if (_email != null && _password != null) {
        final r = await auth.post<Map<String, dynamic>>(
          '$_identityHost/v1/accounts:signInWithPassword',
          queryParameters: {'key': _apiKey},
          data: {
            'email': _email,
            'password': _password,
            'returnSecureToken': true,
          },
        );
        data = r.data!;
      } else {
        final r = await auth.post<Map<String, dynamic>>(
          '$_identityHost/v1/accounts:signUp',
          queryParameters: {'key': _apiKey},
          data: {'returnSecureToken': true},
        );
        data = r.data!;
      }
      _idToken = data['idToken'] as String;
      _refreshToken = data['refreshToken'] as String?;
      final secs = int.tryParse(data['expiresIn'].toString()) ?? 3600;
      _tokenExpiry = DateTime.now().toUtc().add(Duration(seconds: secs));
    } on DioException catch (e) {
      _refreshToken = null;
      final err = toBackendException(e, context: 'Firebase sign-in');
      throw BackendException(err.message, cause: e, isAuth: true);
    }
  }

  @override
  Future<ConnectionCheck> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      final o = await _opts();
      await _dio!.get<Map<String, dynamic>>(
        '$_docsBase/$_collection',
        queryParameters: {'pageSize': 1},
        options: o,
      );
      return ConnectionCheck.success(
        'Firestore reachable, signed in',
        latency: sw.elapsed,
      );
    } catch (e) {
      return ConnectionCheck.failure(
        toBackendException(e, context: 'Firestore').message,
      );
    }
  }

  @override
  Future<SchemaCheck> verifySchema() async {
    // Firestore creates collections lazily; the only thing that can be
    // "missing" is a rules deployment that denies access.
    try {
      final o = await _opts();
      await _dio!.get<Map<String, dynamic>>(
        '$_docsBase/$_collection',
        queryParameters: {'pageSize': 1},
        options: o,
      );
      await _dio!.get<Map<String, dynamic>>(
        '$_docsBase/$_devicesCollection',
        queryParameters: {'pageSize': 1},
        options: o,
      );
      return const SchemaCheck.ready();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return SchemaCheck(
          ok: false,
          missing: const ['security rules'],
          hint: 'Deploy the rules from ${descriptorStatic.docsPath}',
        );
      }
      throw toBackendException(e, context: 'Firestore');
    } catch (e) {
      throw toBackendException(e, context: 'Firestore');
    }
  }

  @override
  Future<void> upsert(List<ClipItem> items) async {
    if (items.isEmpty) return;
    try {
      final o = await _opts();
      final writes = [
        for (final i in items)
          {
            'update': {
              'name':
                  'projects/$_project/databases/(default)/documents/$_collection/${i.id}',
              'fields': _encode(i.toMap()),
            },
          },
      ];
      await _dio!.post<Map<String, dynamic>>(
        '$_docsBase:commit',
        data: {'writes': writes},
        options: o,
      );
    } catch (e) {
      throw toBackendException(e, context: 'Firestore upsert');
    }
  }

  @override
  Future<List<ClipItem>> pullSince(
    DateTime? cursor, {
    required String excludeDeviceId,
    int limit = 500,
  }) async {
    try {
      final o = await _opts();
      final query = <String, Object?>{
        'from': [
          {'collectionId': _collection},
        ],
        'orderBy': [
          {
            'field': {'fieldPath': 'updated_at'},
            'direction': 'ASCENDING',
          },
        ],
        'limit': limit,
        if (cursor != null)
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'updated_at'},
              'op': 'GREATER_THAN',
              'value': {'timestampValue': cursor.toUtc().toIso8601String()},
            },
          },
      };
      final r = await _dio!.post<List<dynamic>>(
        '$_docsBase:runQuery',
        data: {'structuredQuery': query},
        options: o,
      );
      final out = <ClipItem>[];
      for (final row in (r.data ?? const []).cast<Map<String, dynamic>>()) {
        final doc = row['document'];
        if (doc is! Map<String, dynamic>) continue;
        final item = ClipItem.fromMap(
          _decode(doc['fields'] as Map<String, dynamic>? ?? const {}),
        );
        if (item.deviceId != excludeDeviceId) out.add(item);
      }
      return out;
    } catch (e) {
      throw toBackendException(e, context: 'Firestore pull');
    }
  }

  @override
  Stream<ClipItem> watch({required String excludeDeviceId}) =>
      const Stream.empty();

  @override
  Future<void> tombstone(String id, DateTime now) async {
    try {
      final o = await _opts();
      final ts = now.toUtc().toIso8601String();
      await _dio!.patch<Map<String, dynamic>>(
        '$_docsBase/$_collection/$id',
        queryParameters: {
          'updateMask.fieldPaths': ['deleted_at', 'updated_at', 'content'],
          'currentDocument.exists': 'true',
        },
        data: {
          'fields': _encode({
            'deleted_at': ts,
            'updated_at': ts,
            'content': '',
          }),
        },
        options: o.copyWith(validateStatus: (s) => s == 200 || s == 404),
      );
    } catch (e) {
      throw toBackendException(e, context: 'Firestore tombstone');
    }
  }

  @override
  Future<void> registerDevice(Device device) async {
    try {
      final o = await _opts();
      await _dio!.patch<Map<String, dynamic>>(
        '$_docsBase/$_devicesCollection/${device.id}',
        data: {'fields': _encode(device.toMap())},
        options: o,
      );
    } catch (e) {
      throw toBackendException(e, context: 'Firestore device');
    }
  }

  @override
  Future<List<Device>> listDevices() async {
    try {
      final o = await _opts();
      final r = await _dio!.get<Map<String, dynamic>>(
        '$_docsBase/$_devicesCollection',
        queryParameters: {'pageSize': 200},
        options: o,
      );
      final docs = (r.data?['documents'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      return docs
          .map(
            (d) => Device.fromMap(
              _decode(d['fields'] as Map<String, dynamic>? ?? const {}),
            ),
          )
          .toList();
    } catch (e) {
      throw toBackendException(e, context: 'Firestore devices');
    }
  }

  @override
  Future<int> purgeBefore(DateTime before) async {
    try {
      final o = await _opts();
      final r = await _dio!.post<List<dynamic>>(
        '$_docsBase:runQuery',
        data: {
          'structuredQuery': {
            'from': [
              {'collectionId': _collection},
            ],
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': 'updated_at'},
                'op': 'LESS_THAN',
                'value': {'timestampValue': before.toUtc().toIso8601String()},
              },
            },
            'select': {
              'fields': [
                {'fieldPath': '__name__'},
              ],
            },
            'limit': 500,
          },
        },
        options: o,
      );
      final names = <String>[
        for (final row in (r.data ?? const []).cast<Map<String, dynamic>>())
          if (row['document'] is Map)
            (row['document'] as Map)['name'] as String,
      ];
      if (names.isEmpty) return 0;
      await _dio!.post<Map<String, dynamic>>(
        '$_docsBase:commit',
        data: {
          'writes': [
            for (final n in names) {'delete': n},
          ],
        },
        options: o,
      );
      return names.length;
    } catch (e) {
      throw toBackendException(e, context: 'Firestore purge');
    }
  }

  @override
  Future<void> dispose() async {
    if (_injectedDio == null) _dio?.close(force: true);
    if (_injectedAuthDio == null) _auth?.close(force: true);
    _dio = null;
    _auth = null;
    _idToken = null;
    _refreshToken = null;
  }

  // --- Firestore typed-value encoding -------------------------------------

  static const _timestampKeys = {
    'created_at',
    'updated_at',
    'deleted_at',
    'last_seen',
  };

  static Map<String, Object?> _encode(Map<String, Object?> m) => {
    for (final e in m.entries) e.key: _encodeValue(e.key, e.value),
  };

  static Map<String, Object?> _encodeValue(String key, Object? v) =>
      switch (v) {
        null => {'nullValue': null},
        final bool b => {'booleanValue': b},
        final int i => {'integerValue': '$i'},
        final double d => {'doubleValue': d},
        final String s when _timestampKeys.contains(key) => {
          'timestampValue': s,
        },
        final String s => {'stringValue': s},
        _ => {'stringValue': v.toString()},
      };

  static Map<String, Object?> _decode(Map<String, dynamic> fields) => {
    for (final e in fields.entries)
      e.key: _decodeValue(e.value as Map<String, dynamic>),
  };

  static Object? _decodeValue(Map<String, dynamic> v) {
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('timestampValue')) return v['timestampValue'];
    if (v.containsKey('integerValue')) {
      return int.tryParse(v['integerValue'].toString());
    }
    if (v.containsKey('doubleValue')) {
      return (v['doubleValue'] as num).toDouble();
    }
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    return null;
  }
}
