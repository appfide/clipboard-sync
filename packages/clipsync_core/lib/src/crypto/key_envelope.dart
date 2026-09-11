import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:clipsync_core/src/crypto/device_keys.dart';
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// A passphrase sealed to one device's X25519 key.
///
/// `shared = X25519(ephemeral, recipient)`,
/// `key = HKDF-SHA256(shared, salt = ephPub || recipientPub, info = "clipsync-envelope-v1")`,
/// `ct = AES-256-GCM(key, nonce, passphrase, aad = version)`.
///
/// The envelope itself is covered by the admin signature on the device row,
/// so an attacker with database access cannot swap it for one holding a
/// passphrase of their choosing.
@immutable
class KeyEnvelope {
  /// Creates an envelope.
  const KeyEnvelope({
    required this.version,
    required this.ephemeralPub,
    required this.nonce,
    required this.ciphertext,
  });

  /// Parses [encode]d form.
  factory KeyEnvelope.decode(String s) {
    final j = jsonDecode(s) as Map<String, Object?>;
    return KeyEnvelope(
      version: j['v']! as int,
      ephemeralPub: j['e']! as String,
      nonce: j['n']! as String,
      ciphertext: j['c']! as String,
    );
  }

  /// Passphrase version this envelope carries.
  final int version;

  /// Ephemeral X25519 public key, base64.
  final String ephemeralPub;

  /// AES-GCM nonce, base64.
  final String nonce;

  /// Ciphertext || tag, base64.
  final String ciphertext;

  static final X25519 _x = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static const _info = 'clipsync-envelope-v1';

  /// Compact JSON.
  String encode() => jsonEncode({
    'v': version,
    'e': ephemeralPub,
    'n': nonce,
    'c': ciphertext,
  });

  /// Seals [passphrase] for the device whose X25519 public key is
  /// [recipientBoxPub] (base64).
  static Future<KeyEnvelope> seal({
    required String passphrase,
    required int version,
    required String recipientBoxPub,
  }) async {
    final eph = await _x.newKeyPair();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final shared = await _x.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(
        base64Decode(recipientBoxPub),
        type: KeyPairType.x25519,
      ),
    );
    final key = await _derive(shared, ephPub, base64Decode(recipientBoxPub));
    final r = Random.secure();
    final nonce = Uint8List.fromList(List.generate(12, (_) => r.nextInt(256)));
    final box = await _aes.encrypt(
      utf8.encode(passphrase),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode('v$version'),
    );
    return KeyEnvelope(
      version: version,
      ephemeralPub: base64Encode(ephPub),
      nonce: base64Encode(nonce),
      ciphertext: base64Encode([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Opens the envelope with the recipient's [keys]. Throws
  /// [EnvelopeException] when it was not sealed for these keys or was
  /// tampered with.
  Future<String> open(DeviceKeys keys) async {
    try {
      final shared = await keys.sharedSecret(ephemeralPub);
      final key = await _derive(
        shared,
        base64Decode(ephemeralPub),
        base64Decode(keys.boxPub),
      );
      final blob = base64Decode(ciphertext);
      if (blob.length < 16) throw EnvelopeException('too short');
      final clear = await _aes.decrypt(
        SecretBox(
          blob.sublist(0, blob.length - 16),
          nonce: base64Decode(nonce),
          mac: Mac(blob.sublist(blob.length - 16)),
        ),
        secretKey: key,
        aad: utf8.encode('v$version'),
      );
      return utf8.decode(clear);
    } on EnvelopeException {
      rethrow;
    } catch (e) {
      throw EnvelopeException('envelope not for this device or damaged');
    }
  }

  static Future<SecretKey> _derive(
    SecretKey shared,
    List<int> ephPub,
    List<int> recipientPub,
  ) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: [...ephPub, ...recipientPub],
    info: utf8.encode(_info),
  );
}

/// Envelope failure.
class EnvelopeException implements Exception {
  /// Creates the exception.
  EnvelopeException(this.message);

  /// Detail.
  final String message;

  @override
  String toString() => 'EnvelopeException: $message';
}
