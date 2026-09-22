import 'dart:convert';
import 'dart:io';

import 'package:clipboard_sync/core/build_info.dart';
import 'package:clipboard_sync/features/downloads/release_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the latest release could not be read, in words a user can act on.
class ReleaseLookupException implements Exception {
  /// Creates the failure.
  const ReleaseLookupException(this.message);

  /// Shown on the download page.
  final String message;

  @override
  String toString() => 'ReleaseLookupException: $message';
}

/// Reads the newest GitHub release for [BuildInfo.repoUrl].
///
/// This is the only request the app makes to anything other than the user's
/// own database, it is unauthenticated, and it only runs when the download
/// page is open.
class ReleaseService {
  /// Creates the service. [clientFactory] exists for tests.
  const ReleaseService({this.clientFactory});

  /// Overridden in tests to serve a canned response.
  final HttpClient Function()? clientFactory;

  /// How long to wait before giving up on GitHub.
  static const timeout = Duration(seconds: 12);

  /// `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
  static Uri get endpoint {
    final slug = Uri.parse(BuildInfo.repoUrl).path;
    return Uri.parse('https://api.github.com/repos$slug/releases/latest');
  }

  /// Fetches and parses the newest release.
  Future<ReleaseInfo> latest() async {
    final client = (clientFactory?.call() ?? HttpClient())
      ..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(endpoint);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(
          HttpHeaders.userAgentHeader,
          'ClipboardSync/${BuildInfo.version}',
        );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      switch (response.statusCode) {
        case 200:
          break;
        case 403:
        case 429:
          throw const ReleaseLookupException(
            'GitHub is rate-limiting this network right now. Open the '
            'releases page in a browser instead.',
          );
        case 404:
          throw const ReleaseLookupException(
            'No published release yet. Check the releases page for builds.',
          );
        default:
          throw ReleaseLookupException(
            'GitHub answered ${response.statusCode}. Open the releases page '
            'in a browser instead.',
          );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        throw const ReleaseLookupException(
          'GitHub sent something unexpected. Open the releases page instead.',
        );
      }
      return ReleaseInfo.fromJson(decoded);
    } on ReleaseLookupException {
      rethrow;
    } on SocketException {
      throw const ReleaseLookupException(
        'Could not reach github.com. Check the connection and try again.',
      );
    } on Object {
      throw const ReleaseLookupException(
        'Could not read the latest release. Open the releases page instead.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// The service; overridden in tests.
final releaseServiceProvider = Provider<ReleaseService>(
  (_) => const ReleaseService(),
);

/// Newest release, fetched once per app run. Refresh with
/// `ref.invalidate(latestReleaseProvider)`.
final latestReleaseProvider = FutureProvider<ReleaseInfo>(
  (ref) => ref.watch(releaseServiceProvider).latest(),
);
