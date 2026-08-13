import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/features/sessions/chat_composer.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Regression coverage for the "composer locks up mid-stream" bug: the text
/// field must stay editable and must not lose/clobber a draft while
/// `sending` is true, and the draft must survive the flag flipping back to
/// false when the turn completes.
Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  required bool sending,
  VoidCallback? onStop,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: ChatComposerBar(
          controller: controller,
          onSend: () {},
          onStop: onStop,
          sending: sending,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('text field stays enabled and editable while sending is true', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pump(tester, controller: controller, sending: true);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.enabled,
      isTrue,
      reason: 'the composer must stay typeable through the whole agent turn',
    );

    await tester.enterText(find.byType(TextField), 'still typing mid-stream');
    await tester.pump();
    expect(controller.text, 'still typing mid-stream');
  });

  testWidgets(
    'a draft typed while sending survives the turn completing (sending '
    'flips back to false)',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, controller: controller, sending: true);
      await tester.enterText(find.byType(TextField), 'my next question');
      await tester.pump();
      expect(controller.text, 'my next question');

      // Turn completes — parent flips `sending` back to false. Rebuilding
      // the composer must not clear or alter the controller's text; only
      // an explicit send should ever do that.
      await _pump(tester, controller: controller, sending: false);
      expect(controller.text, 'my next question');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
    },
  );

  testWidgets('send action is still gated while sending — stop replaces it', (
    tester,
  ) async {
    var stopped = false;
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await _pump(
      tester,
      controller: controller,
      sending: true,
      onStop: () => stopped = true,
    );

    // No upward-arrow send button while sending — it's replaced by stop.
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(stopped, isTrue);
  });

  testWidgets('send button is enabled once not sending and there is text', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hi');
    addTearDown(controller.dispose);

    await _pump(tester, controller: controller, sending: false);

    final sendButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(IconButton),
      ),
    );
    expect(sendButton.onPressed, isNotNull);
  });
}
