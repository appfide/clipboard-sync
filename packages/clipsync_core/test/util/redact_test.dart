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

  group('heuristics', _secretHeuristics);
}

void _secretHeuristics() {
  test('looksLikeSecret flags credentials, not prose', () {
    const prose =
        'Meet at 10:30 tomorrow, bring the slides and a password for the wifi is on the board.';
    expect(looksLikeSecret(prose), isFalse);
    expect(looksLikeSecret('https://example.com/path?q=1'), isFalse);
    expect(looksLikeSecret('sk-abc'), isFalse, reason: 'too short');
    expect(looksLikeSecret(['AKIA', 'ABCDEFGHIJKLMNOP'].join()), isTrue);
    expect(looksLikeSecret('ghp_${'a' * 36}'), isTrue);
    expect(looksLikeSecret('xoxb-1234567890-abcdef'), isTrue);
    expect(looksLikeSecret('sk-${'z' * 24}'), isTrue);
    expect(looksLikeSecret('AIza${'A' * 35}'), isTrue);
    expect(
      looksLikeSecret('mongodb+srv://u:p@cluster0.example.com/db'),
      isTrue,
    );
    expect(looksLikeSecret('password: hunter22'), isTrue);
    expect(
      looksLikeSecret(
        ['-----BEGIN ', 'RSA PRIVATE ', 'KEY-----\nMIIE...\n-----END'].join(),
      ),
      isTrue,
    );
    expect(looksLikeSecret(_jwt), isTrue);
  });
}
