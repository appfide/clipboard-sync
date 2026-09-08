import 'package:clipboard_sync/core/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credential storage. Uses the OS credential store (Keychain / Keystore /
/// DPAPI / libsecret); if that is unavailable on this machine (e.g. an
/// unsigned macOS build without keychain entitlements, or a Linux desktop
/// without a Secret Service) it falls back to app preferences and flags
/// [degraded] so Settings can warn the user.
class SecretStore {
  /// Creates a store.
  SecretStore(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;
  static const _fallbackPrefix = 'secret_fallback.';

  final ValueNotifier<bool> _degraded = ValueNotifier(false);

  /// True once any secure-storage call has failed and the fallback is in use.
  ValueListenable<bool> get degraded => _degraded;

  /// Reads a secret.
  Future<String?> read(String key) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null) return v;
    } on PlatformException catch (e) {
      _fail(e);
    } on MissingPluginException catch (e) {
      _fail(e);
    }
    return _prefs.getString('$_fallbackPrefix$key');
  }

  /// Writes a secret (deletes when [value] is null/empty).
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) return delete(key);
    try {
      await _secure.write(key: key, value: value);
      await _prefs.remove('$_fallbackPrefix$key');
      return;
    } on PlatformException catch (e) {
      _fail(e);
    } on MissingPluginException catch (e) {
      _fail(e);
    }
    await _prefs.setString('$_fallbackPrefix$key', value);
  }

  /// Deletes a secret from both locations.
  Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } on PlatformException catch (e) {
      _fail(e);
    } on MissingPluginException catch (e) {
      _fail(e);
    }
    await _prefs.remove('$_fallbackPrefix$key');
  }

  void _fail(Object e) {
    if (!_degraded.value) {
      log.w(
        'OS credential store unavailable, using app preferences fallback',
        error: e,
      );
      _degraded.value = true;
    }
  }
}
