import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

void main() {
  group('describeNetworkFailure', () {
    test('names the host a DNS failure could not resolve', () {
      // Verbatim shape of what package:http throws through supabase.
      const raw =
          'ClientException with SocketException: Failed host lookup: '
          "'abcdefghij.supabase.co' (OS Error: nodename nor servname provided, "
          'or not known, errno = 8), '
          'uri=https://abcdefghij.supabase.co/rest/v1/devices?on_conflict=id';

      final message = describeNetworkFailure(raw);

      expect(message, isNotNull);
      expect(message, contains('abcdefghij.supabase.co'));
      expect(message, contains('deleted'));
      expect(message, contains('Settings'));
      expect(message, isNot(contains('errno')));
      expect(message, isNot(contains('SocketException')));
    });

    test('falls back to the uri when the host is not quoted', () {
      const raw =
          'SocketException: Connection refused (OS Error: Connection refused, '
          'errno = 61), uri=https://db.example.org:8443/api';

      final message = describeNetworkFailure(raw);

      expect(message, contains('db.example.org'));
      expect(message, contains('down'));
    });

    test('covers timeouts, unreachable networks and bad certificates', () {
      expect(
        describeNetworkFailure('SocketException: Operation timed out'),
        contains('Cannot reach the database'),
      );
      expect(
        describeNetworkFailure('SocketException: Network is unreachable'),
        contains('Cannot reach'),
      );
      expect(
        describeNetworkFailure('HandshakeException: CERTIFICATE_VERIFY_FAILED'),
        contains('Secure connection'),
      );
    });

    test('leaves anything that is not a transport failure alone', () {
      expect(
        describeNetworkFailure('PostgrestException: column missing'),
        isNull,
      );
      expect(describeNetworkFailure('HTTP 401: invalid api key'), isNull);
    });
  });

  group('toBackendException', () {
    test('keeps the adapter prefix and drops the raw socket text', () {
      const raw =
          'ClientException with SocketException: Failed host lookup: '
          "'gone.supabase.co', uri=https://gone.supabase.co/rest/v1/devices";

      final e = toBackendException(raw, context: 'Supabase');

      expect(e.message, startsWith('Supabase: '));
      expect(e.message, contains('gone.supabase.co'));
      expect(e.message, isNot(contains('ClientException')));
      expect(e.isTransient, isTrue);
      expect(e.cause, raw, reason: 'the raw error still reaches diagnostics');
    });

    test('passes a BackendException through untouched', () {
      final original = BackendException('already friendly');
      expect(toBackendException(original), same(original));
    });
  });
}
