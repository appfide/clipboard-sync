import 'package:clipsync_core/src/crypto/clip_cipher.dart';

/// Every passphrase version this device knows, so history sealed before a
/// rotation stays readable while new items use the newest key.
class CipherRing {
  /// Creates a ring; add versions with [add].
  CipherRing();

  final Map<int, ClipCipher> _ciphers = {};
  int _current = 0;

  /// Builds a ring from `{version: passphrase}` for [keyScope].
  static Future<CipherRing> fromPassphrases(
    Map<int, String> passphrases, {
    required String keyScope,
  }) async {
    final ring = CipherRing();
    for (final e in passphrases.entries) {
      ring.add(
        e.key,
        await ClipCipher.fromPassphrase(e.value, keyScope: keyScope),
      );
    }
    return ring;
  }

  /// Newest version, or 0 when empty.
  int get currentVersion => _current;

  /// Cipher used to seal new items, or `null` when the ring is empty.
  ClipCipher? get current => _ciphers[_current];

  /// Cipher for [version], or `null` when unknown.
  ClipCipher? cipherFor(int version) => _ciphers[version];

  /// Whether the ring has no keys.
  bool get isEmpty => _ciphers.isEmpty;

  /// Known versions.
  Iterable<int> get versions => _ciphers.keys;

  /// Adds or replaces [version]; becomes current when newest.
  void add(int version, ClipCipher cipher) {
    _ciphers[version] = cipher;
    if (version > _current) _current = version;
  }
}
