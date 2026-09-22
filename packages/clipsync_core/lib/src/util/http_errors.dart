import 'package:clipsync_core/src/backend/sync_backend.dart';
import 'package:clipsync_core/src/util/redact.dart';
import 'package:dio/dio.dart';

/// Host named by a transport error, from the `Failed host lookup: 'x'` part or
/// the `uri=` the HTTP clients append.
String? _failingHost(String text) {
  final lookup = RegExp("host lookup: '([^']+)'").firstMatch(text);
  if (lookup != null) return lookup.group(1);
  final uri = RegExp(r'uri=(\S+)').firstMatch(text);
  if (uri != null) {
    final parsed = Uri.tryParse(uri.group(1)!);
    if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
  }
  final url = RegExp(r'https?://([^\s/,)\]]+)').firstMatch(text);
  return url?.group(1);
}

/// Rewrites a transport failure as a sentence that says what to do about it,
/// or returns null when [e] is not one.
///
/// The raw error still travels on [BackendException.cause] and into the
/// diagnostics export; this is only what the user reads.
String? describeNetworkFailure(Object e) {
  final text = e.toString();
  final host = _failingHost(text);
  final target = host ?? 'the database';

  const notFound = [
    'Failed host lookup',
    'No address associated with hostname',
    'nodename nor servname provided',
    'Name or service not known',
  ];
  const unreachable = [
    'Connection refused',
    'Connection timed out',
    'Operation timed out',
    'Network is unreachable',
    'No route to host',
    'Software caused connection abort',
    'Connection reset by peer',
    'Connection closed before full header was received',
  ];

  if (notFound.any(text.contains)) {
    return 'Cannot find $target. The database may have been deleted or the '
        'URL mistyped — check Settings → Database. If the URL is right, this '
        'device may be offline.';
  }
  if (unreachable.any(text.contains)) {
    return 'Cannot reach $target. It may be down, or this network may be '
        'blocking it.';
  }
  if (text.contains('HandshakeException') ||
      text.contains('CERTIFICATE_VERIFY_FAILED')) {
    return 'Secure connection to $target failed. Check the URL and any proxy '
        'on this network.';
  }
  return null;
}

/// Converts any error from an HTTP-based adapter into a [BackendException]
/// with auth/transient classification and redacted text.
BackendException toBackendException(Object e, {String? context}) {
  if (e is BackendException) return e;
  final prefix = context == null ? '' : '$context: ';
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == null) {
      final network = describeNetworkFailure(e.error ?? e);
      if (network != null) {
        return BackendException(
          '$prefix$network',
          cause: e,
          isTransient: true,
        );
      }
    }
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
  final network = describeNetworkFailure(e);
  return BackendException(
    network != null ? '$prefix$network' : redactSecrets('$prefix$e'),
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
