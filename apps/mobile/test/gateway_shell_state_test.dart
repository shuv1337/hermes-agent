import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/shell/gateway_shell.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

void main() {
  testWidgets('switching tabs retains the current Sessions screen state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionProfileProvider.overrideWithValue(
            const AsyncData<ConnectionProfile?>(null),
          ),
          sessionSyncProvider.overrideWithValue(null),
          gatewayRealtimeProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GatewayShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final composer = find.byType(EditableText).first;
    await tester.enterText(composer, 'unfinished thought');
    expect(find.text('unfinished thought'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Jobs'), findsWidgets);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(find.text('unfinished thought'), findsOneWidget);
  });
}
