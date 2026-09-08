import 'dart:async';
import 'dart:ui';

import 'package:clipboard_sync/app/app.dart';
import 'package:clipboard_sync/app/router.dart';
import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/platform/desktop_shell.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wires services and runs the app.
Future<void> bootstrap(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) =>
      log.e('flutter error', error: d.exception, stack: d.stack);
  PlatformDispatcher.instance.onError = (e, st) {
    log.e('uncaught', error: e, stack: st);
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // Preferences only: the OS credential store is read after the first frame
  // so a keychain prompt (unsigned macOS builds) can never block startup.
  var settings = await container
      .read(settingsRepositoryProvider)
      .load(includeSecrets: false);
  // Debug/screenshot convenience: `--theme=dark|light` overrides the saved mode for this run.
  final themeArg = args.firstWhere(
    (a) => a.startsWith('--theme='),
    orElse: () => '',
  );
  if (themeArg.isNotEmpty) {
    settings = settings.copyWith(themeMode: themeArg.substring(8));
  }
  container.dispose();

  final startHidden = args.contains('--hidden') || settings.launchHidden;
  await DesktopShell.prepareWindow(
    startHidden: startHidden && settings.onboarded,
  );

  late final ProviderContainer app;
  final shell = PlatformInfo.isDesktop
      ? DesktopShell(
          onSyncNow: () => app.read(syncControllerProvider.notifier).syncNow(),
          onOpenSettings: () => app.read(routerProvider).push('/settings'),
          onQuit: () async {
            await app.read(syncControllerProvider.notifier).syncNow();
            await SystemNavigator.pop();
          },
        )
      : null;

  app = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsProvider.overrideWith(() => SeededSettings(settings)),
      desktopShellProvider.overrideWithValue(shell),
    ],
  );

  runApp(
    UncontrolledProviderScope(container: app, child: const ClipboardSyncApp()),
  );

  await shell?.init(hotkeyEnabled: settings.hotkeyEnabled);
  log.i('started on ${PlatformInfo.name} as ${settings.deviceName}');
  unawaited(_loadSecretsAndStart(app, settings));
}

Future<void> _loadSecretsAndStart(
  ProviderContainer app,
  AppSettings settings,
) async {
  final secrets = await app
      .read(settingsRepositoryProvider)
      .loadBackendValues(settings.backendId);
  app.read(settingsProvider.notifier).seedBackendValues(secrets);
  await app.read(syncControllerProvider.notifier).start();
}
