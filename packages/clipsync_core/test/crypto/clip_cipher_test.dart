import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  group('ClipCipher', () {
    late ClipCipher cipher;
    setUpAll(() async {
      cipher = await ClipCipher.fromPassphrase(
        'correct horse',
        keyScope: 'test',
      );
    });

    test('seal/open round-trip keeps ordering metadata in clear', () async {
      final item = textItem('hello world');
      final sealed = await cipher.seal(item);
      expect(sealed.encrypted, isTrue);
      expect(sealed.content, isNot('hello world'));
      expect(sealed.nonce, isNotNull);
      expect(sealed.sizeBytes, item.sizeBytes);
      final opened = await cipher.open(sealed);
      expect(opened.content, 'hello world');
      expect(opened.encrypted, isFalse);
      expect(opened.nonce, isNull);
    });

    test(
      'the hash on an encrypted row is keyed, not the plain digest',
      () async {
        // A bare SHA-256 beside the ciphertext is a guessing oracle for short
        // clips, which is exactly the content worth protecting.
        const text = '123456';
        final item = textItem(text);
        final sealed = await cipher.seal(item);

        expect(sealed.contentHash, isNot(item.contentHash));
        expect(sealed.contentHash, isNot(sha256Hex(text)));
        expect(sealed.contentHash, hasLength(64));

        // ... and the plain hash is what the local store sees again.
        final opened = await cipher.open(sealed);
        expect(opened.contentHash, sha256Hex(text));
        expect(opened.contentHash, item.contentHash);
      },
    );

    test('the keyed hash matches across devices and differs by key', () async {
      final same = await ClipCipher.fromPassphrase(
        'correct horse',
        keyScope: 'test',
      );
      final other = await ClipCipher.fromPassphrase('other', keyScope: 'test');

      final mine = await cipher.contentFingerprint('shared clip');
      expect(
        await same.contentFingerprint('shared clip'),
        mine,
        reason: 'de-duplication across devices in the group still works',
      );
      expect(await other.contentFingerprint('shared clip'), isNot(mine));
      expect(await cipher.contentFingerprint('another clip'), isNot(mine));
    });

    test('seal is idempotent and skips empty content', () async {
      final item = textItem('x');
      final once = await cipher.seal(item);
      expect(identical(await cipher.seal(once), once), isTrue);
      final empty = textItem('').copyWith(content: '');
      expect((await cipher.seal(empty)).encrypted, isFalse);
    });

    test('wrong passphrase fails authentication', () async {
      final sealed = await cipher.seal(textItem('secret'));
      final other = await ClipCipher.fromPassphrase('wrong', keyScope: 'test');
      expect(() => other.open(sealed), throwsA(isA<CipherException>()));
    });

    test('same passphrase, different keyScope → different key', () async {
      final a = await ClipCipher.fromPassphrase(
        'pw',
        keyScope: 'supabase|https://a',
      );
      final b = await ClipCipher.fromPassphrase(
        'pw',
        keyScope: 'supabase|https://b',
      );
      expect(await a.fingerprint(), isNot(await b.fingerprint()));
      final c = await ClipCipher.fromPassphrase(
        'pw',
        keyScope: 'supabase|https://a',
      );
      expect(await a.fingerprint(), await c.fingerprint());
    });

    test('ciphertext is bound to item id (AAD)', () async {
      final sealed = await cipher.seal(textItem('bound'));
      final moved = ClipItem.fromMap(sealed.toMap()..['id'] = 'other-id');
      expect(() => cipher.open(moved), throwsA(isA<CipherException>()));
    });

    test('tampered ciphertext is rejected', () async {
      final sealed = await cipher.seal(textItem('tamper me'));
      final bad = sealed.copyWith(
        content: 'AAAA${sealed.content.substring(4)}',
      );
      expect(() => cipher.open(bad), throwsA(isA<CipherException>()));
    });

    test('rejects empty passphrase and bad key length', () {
      expect(
        () => ClipCipher.fromPassphrase('', keyScope: 'x'),
        throwsArgumentError,
      );
      expect(() => ClipCipher.fromKeyBytes([1, 2, 3]), throwsArgumentError);
    });
  });
}
