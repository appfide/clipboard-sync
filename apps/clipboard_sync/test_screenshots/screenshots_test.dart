// Renders every screen in both themes at desktop and phone sizes and writes
// PNGs to docs/screenshots/. Not part of `flutter test` (lives outside
// test/); regenerate with:
//   flutter test test_screenshots --update-goldens
import 'dart:io';

import 'package:clipboard_sync/app/app_shell.dart';
import 'package:clipboard_sync/app/router.dart';
import 'package:clipboard_sync/data/local/database.dart';
import 'package:clipboard_sync/data/local/local_store.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _LiveSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(
    phase: SyncPhase.idle,
    realtime: true,
    lastSyncAt: DateTime.now().toUtc(),
  );
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File(
    p.join(
      root,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'MaterialIcons-Regular.otf',
    ),
  );
  if (icons.existsSync()) {
    final bytes = await icons.readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  }
}

ClipItem _clip(
  String id,
  String text, {
  required String device,
  required Duration ago,
  ClipContentType type = ClipContentType.text,
}) {
  final t = DateTime.now().toUtc().subtract(ago);
  return ClipItem.create(
    id: id,
    deviceId: device.toLowerCase(),
    deviceName: device,
    type: type,
    content: text,
    contentHash: sha256Hex(text),
    sizeBytes: text.length,
    now: t,
  );
}

Future<AppDatabase> _seededDb() async {
  final db = AppDatabase.withExecutor(NativeDatabase.memory());
  final store = DriftLocalStore(db);
  await store.applyRemote([
    _clip(
      '1',
      'https://github.com/appfide/clipboard-sync/pull/42',
      device: 'MacBook Pro',
      ago: const Duration(minutes: 2),
      type: ClipContentType.url,
    ),
    _clip(
      '2',
      'Deploy notes: bump version, run release workflow, verify SHA256SUMS before announcing.',
      device: 'Pixel 9',
      ago: const Duration(minutes: 14),
    ),
    _clip(
      '3',
      'SELECT id, updated_at FROM clip_items WHERE device_id <> :me ORDER BY updated_at ASC LIMIT 500;',
      device: 'Work PC',
      ago: const Duration(hours: 1),
    ),
    _clip(
      '4',
      'Meeting moved to 15:30 — same room. Bring the packaging checklist.',
      device: 'iPhone',
      ago: const Duration(hours: 3),
    ),
    _clip(
      '5',
      'sk-…redacted… (never paste secrets into a shared clipboard)',
      device: 'MacBook Pro',
      ago: const Duration(hours: 5),
    ),
    _clip(
      '6',
      'https://docs.flutter.dev/platform-integration/desktop',
      device: 'Work PC',
      ago: const Duration(days: 1, hours: 2),
      type: ClipContentType.url,
    ),
    _clip(
      '7',
      'Kerala Startup Mission, Kinfra Hi-Tech Park, Kalamassery, Kochi 683503',
      device: 'iPhone',
      ago: const Duration(days: 1, hours: 6),
    ),
  ]);
  await store.setPinned('4', pinned: true);
  await store.capture(
    _clip(
      '8',
      'Just copied on this Mac — waiting to sync',
      device: 'MacBook Pro',
      ago: Duration.zero,
    ),
  );
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A page that never settles must fail fast, not hang the run.
  setUpAll(_loadFonts);

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    required ThemeMode mode,
    required Size size,
    double dpr = 2,
    bool onboarded = true,
  }) async {
    tester.view
      ..physicalSize = size * dpr
      ..devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    // This suite lives outside test/ so the analyzer does not treat it as a test.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await _seededDb();
    final settings = AppSettings(
      deviceId: 'macbook-pro',
      deviceName: 'MacBook Pro',
      onboarded: onboarded,
      backendId: 'supabase',
      backendValues: const {
        'url': 'https://abcdefghij.supabase.co',
        'anon_key': 'sb_publishable_xxxxxxxx',
        'table': 'clip_items',
        'devices_table': 'devices',
      },
      encryptionEnabled: true,
      themeMode: mode.name,
    );
    final router = buildAppRouter(
      onboarded: onboarded,
      initialLocation: location,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          settingsProvider.overrideWith(() => SeededSettings(settings)),
          syncControllerProvider.overrideWith(_LiveSync.new),
          routerProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../docs/screenshots/$name.png'),
    );
    // Drift schedules zero-duration timers when the last stream listener goes
    // away and close() waits on them; under the fake test clock they only
    // fire on pump. So: dispose the tree, pump to run those timers, then
    // close on the real event loop.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(db.close);
  }

  const desktop = Size(1120, 720);
  const phone = Size(390, 844);

  testWidgets(
    'history desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-desktop-light',
      location: '/',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'history desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-desktop-dark',
      location: '/',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'settings desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-desktop-light',
      location: '/settings',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'settings desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-desktop-dark',
      location: '/settings',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'backend desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'backend-desktop-light',
      location: '/settings/backend',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'about desktop light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'about-desktop-light',
      location: '/about',
      mode: ThemeMode.light,
      size: desktop,
    ),
  );
  testWidgets(
    'about desktop dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'about-desktop-dark',
      location: '/about',
      mode: ThemeMode.dark,
      size: desktop,
    ),
  );
  testWidgets(
    'onboarding phone light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'onboarding-phone-light',
      location: '/onboarding',
      mode: ThemeMode.light,
      size: phone,
      dpr: 3,
      onboarded: false,
    ),
  );
  testWidgets(
    'history phone dark',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'history-phone-dark',
      location: '/',
      mode: ThemeMode.dark,
      size: phone,
      dpr: 3,
    ),
  );
  testWidgets(
    'settings phone light',
    timeout: const Timeout(Duration(seconds: 60)),
    (t) => shot(
      t,
      name: 'settings-phone-light',
      location: '/settings',
      mode: ThemeMode.light,
      size: phone,
      dpr: 3,
    ),
  );

  test(
    'AppShell breakpoint constant is sane',
    () => expect(AppTokens.desktopBreakpoint, lessThan(desktop.width)),
  );
  test(
    'shell widget exists',
    () => expect(const AppShell(child: SizedBox()), isA<Widget>()),
  );
}
