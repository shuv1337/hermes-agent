import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/features/bots/create_bot_sheet.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

void main() {
  test('bot names become valid desktop-compatible handles', () {
    expect(botSlugify(' Senior Cat Wrangler! '), 'senior-cat-wrangler');
    expect(botSlugify('tech_no'), 'tech_no');
    expect(botSlugify('---'), isEmpty);
    expect(botSlugify(List.filled(80, 'A').join()), hasLength(64));
  });

  testWidgets('new bot sheet exposes the native creation fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: FilledButton(
                  onPressed: () => showCreateBotSheet(
                    context,
                    existingNames: const {'existing'},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('New Bot'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Create Bot'), findsOneWidget);
  });
}
