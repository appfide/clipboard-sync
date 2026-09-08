import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/data/settings/secret_store.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists [AppSettings]: plain values in `SharedPreferences`, anything a
/// `ConfigField` marks sensitive plus the passphrase in the OS credential
/// store via [SecretStore].
class SettingsRepository {
  /// Creates a repository.
  SettingsRepository(this._prefs, this._secure, this._registry);

  final SharedPreferences _prefs;
  final SecretStore _secure;
  final BackendRegistry _registry;

  static const _kDeviceId = 'device_id';
  static const _kPassphrase = 'e2e_passphrase';
  static String _kSecret(String backendId, String key) =>
      'backend.$backendId.$key';
  static String _kPlain(String backendId, String key) =>
      'backend.$backendId.$key';

  /// Loads settings, creating the device id on first launch.
  Future<AppSettings> load() async {
    var deviceId = await _secure.read(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _secure.write(_kDeviceId, deviceId);
    }
    final backendId = _prefs.getString('backend_id') ?? 'memory';
    return AppSettings(
      deviceId: deviceId,
      deviceName:
          _prefs.getString('device_name') ?? PlatformInfo.defaultDeviceName,
      onboarded: _prefs.getBool('onboarded') ?? false,
      backendId: backendId,
      backendValues: await loadBackendValues(backendId),
      encryptionEnabled: _prefs.getBool('encryption_enabled') ?? false,
      pollIntervalSeconds: _prefs.getInt('poll_interval_seconds') ?? 5,
      retentionDays: _prefs.getInt('retention_days') ?? 30,
      maxInlineKb: _prefs.getInt('max_inline_kb') ?? 1024,
      captureImages: _prefs.getBool('capture_images') ?? true,
      writeIncomingToClipboard: _prefs.getBool('write_incoming') ?? false,
      autoStart: _prefs.getBool('auto_start') ?? false,
      launchHidden: _prefs.getBool('launch_hidden') ?? false,
      hotkeyEnabled: _prefs.getBool('hotkey_enabled') ?? true,
    );
  }

  /// Reads the stored form values for [backendId] (secrets from keychain).
  Future<Map<String, String>> loadBackendValues(String backendId) async {
    final d = _registry.descriptor(backendId);
    if (d == null) return const {};
    final out = <String, String>{};
    for (final f in d.configSchema) {
      final v = f.isSensitive
          ? await _secure.read(_kSecret(backendId, f.key))
          : _prefs.getString(_kPlain(backendId, f.key));
      if (v != null && v.isNotEmpty) {
        out[f.key] = v;
      } else if (f.defaultValue != null) {
        out[f.key] = f.defaultValue.toString();
      }
    }
    return out;
  }

  /// Persists everything in [s].
  Future<void> save(AppSettings s) async {
    await _prefs.setString('device_name', s.deviceName);
    await _prefs.setBool('onboarded', s.onboarded);
    await _prefs.setString('backend_id', s.backendId);
    await _prefs.setBool('encryption_enabled', s.encryptionEnabled);
    await _prefs.setInt('poll_interval_seconds', s.pollIntervalSeconds);
    await _prefs.setInt('retention_days', s.retentionDays);
    await _prefs.setInt('max_inline_kb', s.maxInlineKb);
    await _prefs.setBool('capture_images', s.captureImages);
    await _prefs.setBool('write_incoming', s.writeIncomingToClipboard);
    await _prefs.setBool('auto_start', s.autoStart);
    await _prefs.setBool('launch_hidden', s.launchHidden);
    await _prefs.setBool('hotkey_enabled', s.hotkeyEnabled);
    await saveBackendValues(s.backendId, s.backendValues);
  }

  /// Persists form values for one backend, routing secrets to the keychain.
  Future<void> saveBackendValues(
    String backendId,
    Map<String, String> values,
  ) async {
    final d = _registry.descriptor(backendId);
    if (d == null) return;
    for (final f in d.configSchema) {
      final v = values[f.key]?.trim() ?? '';
      if (f.isSensitive) {
        await _secure.write(_kSecret(backendId, f.key), v);
      } else {
        if (v.isEmpty) {
          await _prefs.remove(_kPlain(backendId, f.key));
        } else {
          await _prefs.setString(_kPlain(backendId, f.key), v);
        }
      }
    }
  }

  /// E2E passphrase from the keychain.
  Future<String?> loadPassphrase() => _secure.read(_kPassphrase);

  /// Stores or clears the passphrase.
  Future<void> savePassphrase(String? passphrase) =>
      _secure.write(_kPassphrase, passphrase);
}
