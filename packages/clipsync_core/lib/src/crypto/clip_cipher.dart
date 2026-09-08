import 'dart:convert';
import 'dart:typed_data';

import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// End-to-end encryption for clipboard payloads.
///
/// Scheme: `key = Argon2id(passphrase, salt = SHA-256("clipsync-v1|" + keyScope))`
/// then `AES-256-GCM(key, nonce = 12 random bytes, aad = item.id)`.
///
/// * `keyScope` ties the key to one sync group (the backend id + primary URL)
///   so the same passphrase on two different databases yields two keys.
/// * The item id is bound as associated data, so a ciphertext cannot be
///   re-attached to a different record without detection.
/// * Only `content` is encrypted; metadata (type, size, hash, timestamps)
///   stays in clear so the engine can de-duplicate and order without the key.
///
/// The derived key never leaves memory; the app stores the *passphrase* in the
/// OS credential store and re-derives on launch.
@immutable
class ClipCipher {
  const ClipCipher._(this._key);

  /// Derives a cipher from [passphrase] for [keyScope].
  ///
  /// Argon2id parameters follow the OWASP minimum (19 MiB, t=2, p=1) so
  /// derivation stays under a second on low-end phones.
  static Future<ClipCipher> fromPassphrase(
    String passphrase, {
    required String keyScope,
  }) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    final salt = crypto.sha256
        .convert(utf8.encode('clipsync-v1|$keyScope'))
        .bytes;
    final argon = Argon2id(
      memory: 19 * 1024, // KiB
      parallelism: 1,
      iterations: 2,
      hashLength: 32,
    );
    final key = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return ClipCipher._(key);
  }

  /// Creates a cipher from raw 32-byte key material (tests / key export).
  static ClipCipher fromKeyBytes(List<int> keyBytes) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(
        keyBytes.length,
        'keyBytes.length',
        'must be 32',
      );
    }
    return ClipCipher._(SecretKey(keyBytes));
  }

  final SecretKey _key;
  static final AesGcm _aes = AesGcm.with256bits();

  /// Fingerprint of the key (first 8 hex chars of SHA-256 of the key bytes),
  /// shown in settings so users can confirm two devices share a passphrase.
  Future<String> fingerprint() async {
    final bytes = await _key.extractBytes();
    return crypto.sha256.convert(bytes).toString().substring(0, 8);
  }

  /// Encrypts [item]'s content. Returns the item unchanged if already
  /// encrypted or a tombstone with no content.
  Future<ClipItem> seal(ClipItem item) async {
    if (item.encrypted || item.content.isEmpty) return item;
    final box = await _aes.encrypt(
      utf8.encode(item.content),
      secretKey: _key,
      aad: utf8.encode(item.id),
    );
    // Store ciphertext || mac as one base64 blob; nonce separately.
    final payload = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return item.copyWith(
      content: base64Encode(payload),
      nonce: base64Encode(box.nonce),
      encrypted: true,
    );
  }

  /// Decrypts [item]'s content. Returns the item unchanged if not encrypted.
  ///
  /// Throws [CipherException] on wrong key or tampering.
  Future<ClipItem> open(ClipItem item) async {
    if (!item.encrypted) return item;
    if (item.content.isEmpty) {
      return item.copyWith(encrypted: false, clearNonce: true);
    }
    final nonce = item.nonce;
    if (nonce == null) throw CipherException('Missing nonce on ${item.id}');
    try {
      final payload = base64Decode(item.content);
      if (payload.length < 16) throw CipherException('Ciphertext too short');
      final box = SecretBox(
        payload.sublist(0, payload.length - 16),
        nonce: base64Decode(nonce),
        mac: Mac(payload.sublist(payload.length - 16)),
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: _key,
        aad: utf8.encode(item.id),
      );
      return item.copyWith(
        content: utf8.decode(clear),
        encrypted: false,
        clearNonce: true,
      );
    } on SecretBoxAuthenticationError {
      throw CipherException('Wrong passphrase or tampered item ${item.id}');
    } on FormatException catch (e) {
      throw CipherException('Corrupt ciphertext on ${item.id}: ${e.message}');
    }
  }
}

/// Decryption failure — wrong passphrase, tampering or corruption.
class CipherException implements Exception {
  /// Creates a cipher exception.
  CipherException(this.message);

  /// Detail.
  final String message;

  @override
  String toString() => 'CipherException: $message';
}
