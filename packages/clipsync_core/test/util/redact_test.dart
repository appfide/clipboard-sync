import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

// Fixtures are assembled at runtime so no scanner-matchable secret literal
// ever exists in the repository.
final String _jwt = [
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9',
  'eyJzdWIiOiIxMjM0NTY3ODkwIn0',
  'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c',
].join('.');
final String _apiKey = [
  'AI',
  'za',
  'SyD_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAK',
].join();
final String _uri = [
  'mongodb+srv:',
  '//bob:hunter2@cluster.example.net/db',
].join();
final String _sbKey = ['sb_', 'secret_', 'abcdefghijklmnopqrstuvwxyz'].join();

void main() {
  test('masks JWTs, api keys, url credentials and key=value secrets', () {
    final out = redactSecrets(
      '$_jwt $_apiKey $_uri password=SuperSecret123 $_sbKey',
    );
    expect(out, isNot(contains('SflKxwRJ')));
    expect(out, isNot(contains('FAKEFAKE')));
    expect(out, isNot(contains('hunter2')));
    expect(out, isNot(contains('SuperSecret123')));
    expect(out, isNot(contains('abcdefghijklmnop')));
    expect(out, contains('cluster.example.net'));
  });

  test('leaves ordinary text alone', () {
    const s = 'pushed 3 item(s) to https://example.com/api';
    expect(redactSecrets(s), s);
  });
}
