import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/util/redact.dart';
import 'package:dio/dio.dart';

/// Converts any error from an HTTP-based adapter into a [BackendException]
/// with auth/transient classification and redacted text.
BackendException toBackendException(Object e, {String? context}) {
  if (e is BackendException) return e;
  final prefix = context == null ? '' : '$context: ';
  if (e is DioException) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final detail = body is Map
        ? (body['message'] ?? body['error'] ?? body['reason'] ?? body)
              .toString()
        : body?.toString();
    final msg = redactSecrets(
      '$prefix${e.message ?? e.type.name}${code != null ? ' (HTTP $code)' : ''}${detail != null && detail.isNotEmpty ? ': $detail' : ''}',
    );
    return BackendException(
      msg,
      cause: e,
      isAuth: code == 401 || code == 403,
      isTransient: code == null || code == 408 || code == 429 || code >= 500,
    );
  }
  return BackendException(
    redactSecrets('$prefix$e'),
    cause: e,
    isTransient: true,
  );
}

/// Shared [Dio] factory with sane timeouts and no default logging.
Dio newDio({String? baseUrl, Map<String, String>? headers}) => Dio(
  BaseOptions(
    baseUrl: baseUrl ?? '',
    headers: headers,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ),
);
