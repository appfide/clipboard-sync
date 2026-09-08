import 'package:clipboard_sync/features/about/about_page.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('About page renders company facts in $name theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const AboutPage()),
      );
      expect(find.text('Clipboard Sync'), findsOneWidget);
      expect(find.text('Building from Kerala,\nfor the World'), findsOneWidget);
      expect(find.byType(ActionChip), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Privacy Policy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('appfide.com'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });
  }

  test('themes expose AppColors extension with AA-friendly muted text', () {
    for (final t in [AppTheme.light(), AppTheme.dark()]) {
      final colors = t.extension<AppColors>()!;
      final bg = t.colorScheme.surface;
      expect(
        _contrast(colors.muted, bg),
        greaterThanOrEqualTo(4.5),
        reason: '${t.brightness} muted text contrast',
      );
      expect(
        _contrast(t.colorScheme.onSurface, bg),
        greaterThanOrEqualTo(7),
        reason: '${t.brightness} body text contrast',
      );
    }
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
