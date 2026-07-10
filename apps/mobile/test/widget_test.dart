import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/connect/connect_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

void main() {
  testWidgets('Connect screen boots without a saved profile', (tester) async {
    await tester.pumpWidget(
      HermesMobileApp(
        providerOverrides: [
          connectionStoreProvider.overrideWithValue(ConnectionStore.memory()),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Gateway base URL'), findsOneWidget);
    expect(find.textContaining('No API key'), findsOneWidget);
    expect(
      find.text(
        'Unofficial · Community-built · Not affiliated with Nous Research',
      ),
      findsOneWidget,
    );
    expect(find.text('Privacy & data'), findsOneWidget);

    await tester.tap(find.text('Privacy & data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sends conversations and attachments'),
      findsOneWidget,
    );
    expect(find.textContaining('Publisher action required'), findsOneWidget);
  });

  testWidgets('Connect screen remains scrollable at very large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(3.2),
        ),
        child: HermesMobileApp(
          providerOverrides: [
            connectionStoreProvider.overrideWithValue(ConnectionStore.memory()),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Unofficial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gateway URL remains editable during reauthentication', (
    tester,
  ) async {
    var clipboardText = '';
    final messenger = TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = '${(call.arguments as Map)['text'] ?? ''}';
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
        case 'Clipboard.hasStrings':
          return <String, dynamic>{'value': clipboardText.isNotEmpty};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const profile = ConnectionProfile(
      id: 'gateway-1',
      baseUrl: 'https://old.example.com',
      authMode: 'session',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: supportedAppLocales,
          home: ConnectScreen(reauth: true, existingProfile: profile),
        ),
      ),
    );
    await tester.pump();

    final field = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(field).enabled, isTrue);
    await Clipboard.setData(
      const ClipboardData(text: 'https://new.example.com'),
    );
    await tester.tap(field);
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    await editable.pasteText(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();
    expect(
      editable.widget.controller.text,
      contains('https://new.example.com'),
    );
    expect(tester.takeException(), isNull);
  });
}
