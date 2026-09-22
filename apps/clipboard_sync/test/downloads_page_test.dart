import 'dart:convert';

import 'package:clipboard_sync/features/downloads/downloads_page.dart';
import 'package:clipboard_sync/features/downloads/release_info.dart';
import 'package:clipboard_sync/features/downloads/release_service.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape of a real `releases/latest` payload, trimmed to what is read.
Map<String, Object?> _payload({String tag = 'v9.9.9'}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/appfide/clipboard-sync/releases/tag/$tag',
  'published_at': DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 2))
      .toIso8601String(),
  'assets': [
    for (final (name, size) in [
      ('ClipboardSync-9.9.9-macos.dmg', 41943040),
      ('ClipboardSync-9.9.9-windows.exe', 33554432),
      ('ClipboardSync-9.9.9-windows.zip', 31457280),
      ('ClipboardSync-9.9.9-linux.deb', 29360128),
      ('ClipboardSync-9.9.9-linux.AppImage', 52428800),
      ('ClipboardSync-9.9.9-android.apk', 25165824),
      ('ClipboardSync-9.9.9-android.aab', 24117248),
      ('ClipboardSync-9.9.9-ios-unsigned.ipa', 27262976),
      ('SHA256SUMS.txt', 512),
    ])
      {
        'name': name,
        'size': size,
        'browser_download_url':
            'https://github.com/appfide/clipboard-sync/releases/download/$tag/$name',
      },
  ],
};

/// The page is a long list; give the test surface room so every section is
/// laid out instead of being scrolled out of the viewport.
void _tallSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1000, 2600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(ReleaseInfo? release, {Exception? error}) => ProviderScope(
  overrides: [
    latestReleaseProvider.overrideWith((ref) async {
      if (error != null) throw error;
      return release!;
    }),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: const DownloadsPage()),
);

void main() {
  group('ReleaseInfo.fromJson', () {
    test('maps every installer to its platform', () {
      final release = ReleaseInfo.fromJson(_payload());

      expect(release.version, '9.9.9');
      expect(release.platforms, DownloadPlatform.values);
      expect(
        release.forPlatform(DownloadPlatform.macos).single.label,
        contains('.dmg'),
      );
      expect(
        release.forPlatform(DownloadPlatform.windows).map((a) => a.label),
        containsAll(['Installer (.exe)', 'Portable (.zip)']),
      );
      expect(release.forPlatform(DownloadPlatform.linux), hasLength(2));
      expect(release.forPlatform(DownloadPlatform.ios).single.note, isNotNull);
    });

    test(
      'drops the aab, which nobody can install, and lifts the checksums',
      () {
        final release = ReleaseInfo.fromJson(_payload());

        expect(release.assets.any((a) => a.name.endsWith('.aab')), isFalse);
        expect(release.forPlatform(DownloadPlatform.android), hasLength(1));
        expect(release.checksumsUrl, endsWith('SHA256SUMS.txt'));
      },
    );

    test('survives a release with no assets at all', () {
      final release = ReleaseInfo.fromJson({'tag_name': 'v1.0.0'});

      expect(release.assets, isEmpty);
      expect(release.platforms, isEmpty);
      expect(release.checksumsUrl, isNull);
    });

    test('reports sizes in the unit that fits', () {
      final release = ReleaseInfo.fromJson(_payload());
      final dmg = release.forPlatform(DownloadPlatform.macos).single;

      expect(dmg.sizeLabel, '40.0 MB');
      expect(
        const DownloadAsset(
          name: 'x',
          url: 'x',
          sizeBytes: 0,
          platform: DownloadPlatform.linux,
          label: 'x',
        ).sizeLabel,
        isEmpty,
      );
    });
  });

  group('isNewerThan', () {
    ReleaseInfo at(String version) =>
        ReleaseInfo(version: version, htmlUrl: '', assets: const []);

    test('compares each component, not the string', () {
      expect(at('0.10.0').isNewerThan('0.9.9'), isTrue);
      expect(at('1.0.0').isNewerThan('0.99.99'), isTrue);
      expect(at('0.2.1').isNewerThan('0.2.1'), isFalse);
      expect(at('0.2.0').isNewerThan('0.2.1'), isFalse);
    });

    test('stays quiet for local builds and odd tags', () {
      expect(at('1.0.0').isNewerThan('dev'), isFalse);
      expect(at('nightly').isNewerThan('0.1.0'), isFalse);
    });
  });

  group('DownloadsPage', () {
    testWidgets('lists a section per platform with working rows', (
      tester,
    ) async {
      _tallSurface(tester);
      await tester.pumpWidget(_app(ReleaseInfo.fromJson(_payload())));
      await tester.pumpAndSettle();

      for (final platform in DownloadPlatform.values) {
        expect(
          find.text(platform.label),
          findsOneWidget,
          reason: 'section for ${platform.label}',
        );
      }
      expect(find.text('Clipboard Sync 9.9.9'), findsOneWidget);
      expect(find.text('Disk image (.dmg)'), findsOneWidget);
      expect(find.text('SHA256SUMS.txt'), findsOneWidget);
    });

    testWidgets('offers a QR code for a link', (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(_app(ReleaseInfo.fromJson(_payload())));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.qr_code_rounded).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('download-qr-dialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-qr')), findsOneWidget);
      expect(
        find.textContaining('ClipboardSync-9.9.9-macos.dmg'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the releases page when GitHub is unreachable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          null,
          error: const ReleaseLookupException('Could not reach github.com.'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not reach github.com.'), findsOneWidget);
      expect(find.text('Open releases page'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('says so when the release carries no installers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(ReleaseInfo.fromJson({'tag_name': 'v1.0.0'})),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('no installers attached'), findsOneWidget);
      expect(find.text('Open releases page'), findsOneWidget);
    });
  });

  group('ReleaseService', () {
    test('asks the API that belongs to the repo in BuildInfo', () {
      expect(
        ReleaseService.endpoint.toString(),
        'https://api.github.com/repos/appfide/clipboard-sync/releases/latest',
      );
    });

    test('parses a body the same way the model does', () {
      final body = jsonEncode(_payload());
      final release = ReleaseInfo.fromJson(
        jsonDecode(body) as Map<String, Object?>,
      );

      expect(release.assets, hasLength(7));
    });
  });
}
