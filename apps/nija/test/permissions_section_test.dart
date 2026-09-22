import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/features/settings/permissions_section.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/platform/clipboard_service.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija_core/nija_core.dart';

class _FakeSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus.stopped();

  @override
  Future<ClipboardProbe> probeClipboard() async => const ClipboardProbe(
    ClipboardAccess.ok,
    'Read 12 characters of text successfully.',
  );
}

void main() {
  testWidgets('shows platform guidance and runs the clipboard test', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncControllerProvider.overrideWith(_FakeSync.new)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PermissionsSection()),
          ),
        ),
      ),
    );
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Not tested yet'), findsOneWidget);
    // Host-specific guidance rows exist (at least the clipboard row on every OS).
    expect(find.text('Clipboard'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('test-clipboard')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Clipboard access works'), findsOneWidget);
    expect(find.textContaining('12 characters'), findsOneWidget);
  });
}
