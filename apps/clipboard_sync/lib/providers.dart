import 'package:clipboard_sync/data/local/database.dart';
import 'package:clipboard_sync/data/local/local_store.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/data/settings/secret_store.dart';
import 'package:clipboard_sync/data/settings/settings_repository.dart';
import 'package:clipboard_sync/platform/autostart_service.dart';
import 'package:clipboard_sync/platform/desktop_shell.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registry of all backends.
final backendRegistryProvider = Provider<BackendRegistry>(
  (_) => BackendRegistry.builtIn(),
);

/// Drift database (overridden in tests with an in-memory executor).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Local store over the database.
final localStoreProvider = Provider<DriftLocalStore>(
  (ref) => DriftLocalStore(ref.watch(databaseProvider)),
);

/// SharedPreferences, initialised in `bootstrap()` and overridden.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('overridden in bootstrap'),
);

/// Secure storage.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(
    // Legacy keychain: the data-protection keychain needs a signed app with
    // keychain-access-groups, which unsigned community builds do not have.
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      usesDataProtectionKeychain: false,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  ),
);

/// Credential store with graceful fallback.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => SecretStore(
    ref.watch(secureStorageProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

/// Settings persistence.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    ref.watch(sharedPreferencesProvider),
    ref.watch(secretStoreProvider),
    ref.watch(backendRegistryProvider),
  ),
);

/// Loaded settings, overridden in `bootstrap()` with the initial value.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Mutates and persists settings.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => throw UnimplementedError('overridden in bootstrap');

  /// Applies [update] and persists.
  Future<void> update(AppSettings Function(AppSettings) update) async {
    final next = update(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
    if (next.autoStart != state.autoStart ||
        next.launchHidden != state.launchHidden) {
      await AutostartService.setEnabled(
        enabled: next.autoStart,
        hidden: next.launchHidden,
      );
    }
  }

  /// Switches backend and loads its stored values.
  Future<void> selectBackend(String backendId) async {
    final values = await ref
        .read(settingsRepositoryProvider)
        .loadBackendValues(backendId);
    await update(
      (s) => s.copyWith(backendId: backendId, backendValues: values),
    );
  }
}

/// Notifier seeded with the settings loaded during `bootstrap()`.
class SeededSettings extends SettingsNotifier {
  /// Creates a notifier whose initial state is the loaded settings.
  SeededSettings(this._seed);
  final AppSettings _seed;
  @override
  AppSettings build() => _seed;
}

/// Desktop shell (tray, hotkey, window); set by bootstrap on desktop.
final desktopShellProvider = Provider<DesktopShell?>((_) => null);

/// History list filtered by the search query.
final historyQueryProvider = NotifierProvider<HistoryQuery, String>(
  HistoryQuery.new,
);

/// Search query notifier.
class HistoryQuery extends Notifier<String> {
  @override
  String build() => '';

  /// Current query.
  String get query => state;

  /// Sets the query.
  set query(String q) => state = q;
}

/// Live history rows.
final historyProvider = StreamProvider<List<HistoryEntry>>(
  (ref) => ref
      .watch(localStoreProvider)
      .watchHistory(query: ref.watch(historyQueryProvider)),
);

/// Unsynced row count.
final pendingCountProvider = StreamProvider<int>(
  (ref) => ref.watch(localStoreProvider).watchPendingCount(),
);
