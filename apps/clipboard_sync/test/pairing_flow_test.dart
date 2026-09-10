import 'package:clipboard_sync/app/router.dart';
import 'package:clipboard_sync/data/local/database.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/features/sync/sync_controller.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A "remote" backend for tests: the in-memory store, but with a non-memory
/// id so the app treats it as a real sync group.
class _TestDb extends MemoryBackend {
  _TestDb(MemoryStore shared) : super(shared: shared);

  static const descriptorStatic = BackendDescriptor(
    id: 'testdb',
    displayName: 'Test database',
    description: 'in-memory',
    docsPath: 'docs/backends/memory.md',
    supportsRealtime: true,
    configSchema: <ConfigField>[
      ConfigField(key: 'url', label: 'URL', kind: ConfigFieldKind.url),
      ConfigField(key: 'token', label: 'Token', kind: ConfigFieldKind.secret),
    ],
  );

  @override
  BackendDescriptor get descriptor => descriptorStatic;
}

class _Node {
  _Node(this.container, this.db);
  final ProviderContainer container;
  final AppDatabase db;

  SyncController get sync => container.read(syncControllerProvider.notifier);

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

/// Builds a fully wired app container around [shared] and starts sync.
/// Runs in real async so isolates (Argon2) and drift complete.
Future<_Node> _boot(
  WidgetTester tester,
  AppSettings seed,
  MemoryStore shared,
) {
  tester.view
    ..physicalSize = const Size(1000, 1800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester
      .runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final registry = BackendRegistry.builtIn()
          ..register(_TestDb.descriptorStatic, () => _TestDb(shared));
        final db = AppDatabase.withExecutor(NativeDatabase.memory());
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            databaseProvider.overrideWithValue(db),
            backendRegistryProvider.overrideWithValue(registry),
            settingsProvider.overrideWith(() => SeededSettings(seed)),
          ],
        );
        await c.read(settingsRepositoryProvider).save(seed);
        await c.read(syncControllerProvider.notifier).start();
        return _Node(c, db);
      })
      .then((n) => n!);
}

Widget _app(_Node n, String location) => UncontrolledProviderScope(
  container: n.container,
  child: MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: buildAppRouter(onboarded: true, initialLocation: location),
  ),
);

/// Lets real async work finish, pumping frames, until [until] matches.
Future<void> _settle(
  WidgetTester tester, {
  Finder? until,
  Duration max = const Duration(seconds: 30),
}) async {
  await tester.runAsync(() async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < max) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
      if (until == null
          ? sw.elapsed.inMilliseconds > 300
          : until.evaluate().isNotEmpty) {
        return;
      }
    }
  });
  // Let route / menu / dialog transitions finish.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

const _hostSettings = AppSettings(
  deviceId: 'host-id',
  deviceName: 'Host',
  onboarded: true,
  backendId: 'testdb',
  backendValues: {'url': 'https://db.example.com', 'token': 't0k3n'},
);

void main() {
  testWidgets('host generates a code, joiner adopts id, role and settings', (
    tester,
  ) async {
    final shared = MemoryStore();
    final host = await _boot(tester, _hostSettings, shared);
    expect(host.sync.canManageDevices, isTrue);
    expect(shared.devices.keys, contains('host-id'));

    final session = (await tester.runAsync(
      () => host.sync.createPairing(
        role: DeviceRole.sendOnly,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    ))!;
    expect(shared.devices[session.deviceId]!.isPending, isTrue);
    expect(shared.devices[session.deviceId]!.role, DeviceRole.sendOnly);
    expect(shared.devices[session.deviceId]!.pairedBy, 'host-id');
    expect(session.code, isNot(contains('t0k3n')));

    final joiner = await _boot(
      tester,
      const AppSettings(
        deviceId: 'old-id',
        deviceName: 'Phone',
        onboarded: true,
      ),
      shared,
    );
    await tester.pumpWidget(_app(joiner, '/settings/devices/join'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('pairing-code')),
      session.code,
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('pairing-pin')),
      '00000000',
    );
    await tester.tap(find.byKey(const ValueKey('unlock-code')));
    await _settle(tester, until: find.byKey(const ValueKey('join-error')));
    expect(find.textContaining('Wrong PIN'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('pairing-pin')),
      session.pin,
    );
    await tester.tap(find.byKey(const ValueKey('unlock-code')));
    await _settle(tester, until: find.byKey(const ValueKey('join-group')));
    expect(find.text('Test database'), findsOneWidget);
    expect(find.text(DeviceRole.sendOnly.label), findsOneWidget);
    expect(find.byKey(const ValueKey('join-passphrase')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('join-group')));
    await _settle(tester);

    final s = joiner.container.read(settingsProvider);
    expect(s.deviceId, session.deviceId);
    expect(s.backendId, 'testdb');
    expect(s.backendValues['token'], 't0k3n');
    // The engine restarted against the group and adopted the invited row.
    await _settle(tester);
    final me = shared.devices[session.deviceId]!;
    expect(me.isPending, isFalse);
    expect(me.name, 'Phone');
    expect(me.role, DeviceRole.sendOnly);
    expect(
      joiner.container.read(syncControllerProvider).role,
      DeviceRole.sendOnly,
    );
    expect(
      joiner.container.read(settingsRepositoryProvider).loadRegisteredScope(),
      s.backendScope,
    );

    // Host blocks the joiner; joiner revokes itself and tells the user.
    await tester.runAsync(() => host.sync.blockDevice(session.deviceId));
    await tester.runAsync(() => joiner.sync.refreshDevices());
    await _settle(tester, until: find.byKey(const ValueKey('revoked-dialog')));
    expect(joiner.container.read(settingsProvider).backendId, 'memory');
    expect(joiner.container.read(settingsProvider).backendValues, isEmpty);
    expect(
      joiner.container.read(settingsRepositoryProvider).loadRegisteredScope(),
      isNull,
    );
    expect(find.text('This device was blocked'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(joiner.container.read(revocationProvider), isNull);

    await tester.runAsync(() async {
      await joiner.dispose();
      await host.dispose();
    });
  });

  testWidgets('devices page lists the group and manages from the menu', (
    tester,
  ) async {
    final shared = MemoryStore();
    shared.devices['other'] = Device(
      id: 'other',
      name: 'Laptop',
      platform: 'linux',
      lastSeen: DateTime.now().toUtc(),
    );
    final node = await _boot(tester, _hostSettings, shared);

    await tester.pumpWidget(_app(node, '/settings/devices'));
    await _settle(tester, until: find.byKey(const ValueKey('device-other')));
    expect(find.byKey(const ValueKey('device-host-id')), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.byKey(const ValueKey('device-menu-host-id')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('device-menu-other')));
    await _settle(tester, until: find.text('Block'));
    await tester.tap(find.text('Block'));
    await _settle(tester, until: find.widgetWithText(FilledButton, 'Block'));
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await _settle(tester, until: find.text('Blocked'));
    expect(shared.devices['other']!.status, DeviceStatus.blocked);

    await tester.tap(find.byKey(const ValueKey('device-menu-other')));
    await _settle(tester, until: find.text('Change role…'));
    await tester.tap(find.text('Change role…'));
    await _settle(
      tester,
      until: find.byKey(const ValueKey('role-receive_only')),
    );
    await tester.tap(find.byKey(const ValueKey('role-receive_only')));
    await _settle(tester);
    expect(shared.devices['other']!.role, DeviceRole.receiveOnly);

    await tester.runAsync(node.dispose);
  });

  testWidgets('pair page shows QR and PIN; cancelling forgets the invite', (
    tester,
  ) async {
    final shared = MemoryStore();
    final node = await _boot(tester, _hostSettings, shared);

    await tester.pumpWidget(_app(node, '/settings/devices/pair'));
    await _settle(tester, until: find.byKey(const ValueKey('generate-code')));
    await tester.tap(find.byKey(const ValueKey('generate-code')));
    await _settle(tester, until: find.byKey(const ValueKey('pairing-qr')));
    expect(find.byKey(const ValueKey('pairing-pin')), findsOneWidget);
    expect(shared.devices.values.where((d) => d.isPending).length, 1);

    await tester.tap(find.text('Cancel invitation'));
    await _settle(tester, until: find.byKey(const ValueKey('generate-code')));
    expect(shared.devices.values.where((d) => d.isPending), isEmpty);

    await tester.runAsync(node.dispose);
  });
}
