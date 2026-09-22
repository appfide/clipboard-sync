import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Short, human-comparable fingerprint of a public key: first 8 hex chars
/// of SHA-256, split `ab12 cd34`.
String keyFingerprint(String publicKeyBase64) {
  final hex = crypto.sha256
      .convert(base64Decode(publicKeyBase64))
      .toString()
      .substring(0, 8);
  return '${hex.substring(0, 4)} ${hex.substring(4)}';
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// This device's cryptographic identity: an Ed25519 signing key (clips and
/// membership are signed with it) and an X25519 key for receiving sealed
/// passphrases. Private seeds live only in the OS credential store.
class DeviceKeys {
  DeviceKeys._(this._sign, this._box, this.signPub, this.boxPub);

  static final Ed25519 _ed = Ed25519();
  static final X25519 _x = X25519();

  final SimpleKeyPair _sign;
  final SimpleKeyPair _box;

  /// Ed25519 public key, base64.
  final String signPub;

  /// X25519 public key, base64.
  final String boxPub;

  /// Generates a fresh identity.
  static Future<DeviceKeys> generate() =>
      fromSeeds(_randomBytes(32), _randomBytes(32));

  /// Rebuilds an identity from its two 32-byte seeds.
  static Future<DeviceKeys> fromSeeds(
    List<int> signSeed,
    List<int> boxSeed,
  ) async {
    final s = await _ed.newKeyPairFromSeed(signSeed);
    final b = await _x.newKeyPairFromSeed(boxSeed);
    return DeviceKeys._(
      s,
      b,
      base64Encode((await s.extractPublicKey()).bytes),
      base64Encode((await b.extractPublicKey()).bytes),
    );
  }

  /// Rebuilds from [encoded] (see [encode]).
  static Future<DeviceKeys> decode(String encoded) async {
    final bytes = base64Decode(encoded);
    if (bytes.length != 64) {
      throw const FormatException('device keys must be 64 bytes');
    }
    return fromSeeds(bytes.sublist(0, 32), bytes.sublist(32));
  }

  /// Both seeds as one base64 string for secure storage / pairing codes.
  Future<String> encode() async {
    final s = await _sign.extractPrivateKeyBytes();
    final b = await _box.extractPrivateKeyBytes();
    return base64Encode([...s, ...b]);
  }

  /// Signs [message]; returns the 64-byte signature, base64.
  Future<String> sign(List<int> message) async =>
      base64Encode((await _ed.sign(message, keyPair: _sign)).bytes);

  /// X25519 shared secret with [remoteBoxPub] (base64).
  Future<SecretKey> sharedSecret(String remoteBoxPub) => _x.sharedSecretKey(
    keyPair: _box,
    remotePublicKey: SimplePublicKey(
      base64Decode(remoteBoxPub),
      type: KeyPairType.x25519,
    ),
  );

  /// Fingerprint of the signing key.
  String get fingerprint => keyFingerprint(signPub);

  /// Verifies an Ed25519 [signature] (base64) over [message] by [publicKey]
  /// (base64). Never throws; malformed input is simply invalid.
  static Future<bool> verify(
    List<int> message, {
    required String signature,
    required String publicKey,
  }) async {
    try {
      final sig = base64Decode(signature);
      final pub = base64Decode(publicKey);
      if (sig.length != 64 || pub.length != 32) return false;
      return await _ed.verify(
        message,
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// The group's admin signing key. Whoever holds it decides membership:
/// every device row's status / role / expiry / public keys / key envelope
/// must carry a signature by this key before other devices honour them.
class AdminKey {
  AdminKey._(this._pair, this.publicKey);

  static final Ed25519 _ed = Ed25519();

  final SimpleKeyPair _pair;

  /// Ed25519 public key, base64. Pinned by every member.
  final String publicKey;

  /// Generates a fresh admin key.
  static Future<AdminKey> generate() => fromSeed(_randomBytes(32));

  /// Rebuilds from a 32-byte seed.
  static Future<AdminKey> fromSeed(List<int> seed) async {
    final p = await _ed.newKeyPairFromSeed(seed);
    return AdminKey._(p, base64Encode((await p.extractPublicKey()).bytes));
  }

  /// Rebuilds from [encode]d form.
  static Future<AdminKey> decode(String encoded) =>
      fromSeed(base64Decode(encoded));

  /// Seed as base64 for secure storage / pairing codes.
  Future<String> encode() async =>
      base64Encode(await _pair.extractPrivateKeyBytes());

  /// Signs [message]; base64.
  Future<String> sign(List<int> message) async =>
      base64Encode((await _ed.sign(message, keyPair: _pair)).bytes);

  /// Fingerprint shown in the UI so members can compare it out of band.
  String get fingerprint => keyFingerprint(publicKey);
}
