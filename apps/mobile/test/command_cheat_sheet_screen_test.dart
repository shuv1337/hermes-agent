import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/settings/command_cheat_sheet_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

class _CommandsStub extends CommandsNotifier {
  _CommandsStub(this.result, {this.throwing = false});
  final List<SlashCommand> result;
  final bool throwing;
  @override
  Future<List<SlashCommand>> build() async {
    if (throwing) throw Exception('offline');
    return result;
  }

  @override
  Future<void> refresh() async {
    if (throwing) {
      state = AsyncError(Exception('offline'), StackTrace.current);
      return;
    }
    state = AsyncData(result);
  }
}

const _sample = [
  SlashCommand(
    name: 'new',
    description: 'Start a new session',
    category: 'Session',
    aliases: ['reset'],
  ),
  SlashCommand(
    name: 'model',
    description: 'Switch models',
    category: 'Session',
  ),
  SlashCommand(
    name: 'config',
    description: 'Edit configuration',
    category: 'Configuration',
    cliOnly: true,
    configGated: true,
  ),
];

void main() {
  testWidgets('categories and commands render', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandsProvider.overrideWith(() => _CommandsStub(_sample)),
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
          home: const CommandCheatSheetScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/model'), findsOneWidget);
    expect(find.text('/config'), findsOneWidget);
  });

  testWidgets('search filters to matching commands only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandsProvider.overrideWith(() => _CommandsStub(_sample)),
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
          home: const CommandCheatSheetScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'new');
    await tester.pumpAndSettle();

    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/model'), findsNothing);
    expect(find.text('/config'), findsNothing);
  });

  testWidgets('error state shows retry button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandsProvider.overrideWith(
            () => _CommandsStub(const [], throwing: true),
          ),
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
          home: const CommandCheatSheetScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't load commands. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });
}
