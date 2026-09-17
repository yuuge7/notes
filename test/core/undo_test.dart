import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/ui/undo.dart';

/// The bar that offers Undo leaves on its own, or it sits over the bottom of
/// every page opened after it.
void main() {
  Future<void> showBar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUndo(
                ScaffoldMessenger.of(context),
                message: 'Note archived',
                onUndo: () async {},
              ),
              child: const Text('Archive'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
  }

  testWidgets('Undo goes after five seconds', (tester) async {
    await showBar(tester);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Note archived'), findsNothing);
  });

  testWidgets('with TalkBack, Undo stays until it is reached', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await showBar(tester);

    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('Note archived'), findsOneWidget);
  });
}
