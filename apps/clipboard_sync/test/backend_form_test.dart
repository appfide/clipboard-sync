import 'package:clipboard_sync/features/settings/backend_form.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders one control per ConfigField and validates', (
    tester,
  ) async {
    Map<String, String>? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackendForm(
              descriptor: SupabaseBackend.descriptorStatic,
              initialValues: const {},
              onChanged: (v) => latest = v,
            ),
          ),
        ),
      ),
    );
    for (final f in SupabaseBackend.descriptorStatic.configSchema) {
      expect(
        find.byKey(ValueKey('field-${f.key}')),
        findsOneWidget,
        reason: f.key,
      );
    }
    // Defaults are pre-filled.
    expect(find.text('clip_items'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('field-url')),
      'not a url',
    );
    await tester.pump();
    expect(find.textContaining('absolute URL'), findsOneWidget);
    expect(latest?['url'], 'not a url');

    await tester.enterText(
      find.byKey(const ValueKey('field-url')),
      'https://abc.supabase.co',
    );
    await tester.pump();
    expect(find.textContaining('absolute URL'), findsNothing);
  });

  testWidgets('secret fields are obscured until revealed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackendForm(
            descriptor: MongoDbBackend.descriptorStatic,
            initialValues: const {'uri': 'mongodb://x'},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    bool obscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('field-uri')),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(obscured(), isFalse);
  });
}
