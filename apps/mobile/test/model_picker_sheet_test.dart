import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/models/model_picker_sheet.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

class _ModelOptionsStub extends ModelOptionsNotifier {
  _ModelOptionsStub(this.options);

  final ModelOptionsResult options;

  @override
  Future<ModelOptionsResult> build() async => options;

  @override
  Future<void> softSync({bool forceRefresh = true, String? sessionId}) async {}
}

void main() {
  testWidgets('picker does not invent controls for a boolean-only gateway', (
    tester,
  ) async {
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'legacy',
          name: 'Legacy gateway',
          models: ['reasoner'],
          capabilities: {
            'reasoner': ModelCapabilities(reasoning: true, fast: false),
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelOptionsProvider.overrideWith(() => _ModelOptionsStub(options)),
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
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: FilledButton(
                onPressed: () => showModelPickerSheet(
                  context,
                  ref,
                  initialModel: 'reasoner',
                  initialProvider: 'legacy',
                  initialReasoningEffort: 'medium',
                  initialFastMode: false,
                ),
                child: const Text('Open legacy picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open legacy picker'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Minimal'), findsNothing);
    expect(
      find.text('This model has no Thinking or Fast options.'),
      findsOneWidget,
    );
  });

  testWidgets('picker renders only server-advertised effort levels', (
    tester,
  ) async {
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'openai-codex',
          name: 'ChatGPT',
          models: ['gpt-5.6-sol'],
          capabilities: {
            'gpt-5.6-sol': ModelCapabilities(
              reasoning: true,
              thinking: false,
              defaultReasoningEffort: 'low',
              reasoningEfforts: [
                ReasoningEffortOption(effort: 'low'),
                ReasoningEffortOption(effort: 'high'),
                ReasoningEffortOption(effort: 'ultra'),
              ],
            ),
          },
        ),
      ],
    );
    ModelPick? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelOptionsProvider.overrideWith(() => _ModelOptionsStub(options)),
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
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showModelPickerSheet(
                    context,
                    ref,
                    initialModel: 'gpt-5.6-sol',
                    initialProvider: 'openai-codex',
                    initialReasoningEffort: 'medium',
                    initialFastMode: false,
                  );
                },
                child: const Text('Open server picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open server picker'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Ultra'), findsOneWidget);
    expect(find.text('Minimal'), findsNothing);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('Extra high'), findsNothing);
    expect(find.text('Max'), findsNothing);

    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();

    expect(result?.reasoningSupported, isTrue);
    expect(result?.reasoningEffort, 'low');
  });

  testWidgets('picker options change with the selected model capabilities', (
    tester,
  ) async {
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'test',
          name: 'Test provider',
          models: ['reasoner', 'variant', 'variant-fast', 'speedster', 'plain'],
          capabilities: {
            'reasoner': ModelCapabilities(
              reasoning: true,
              thinking: true,
              fast: false,
              reasoningEfforts: [
                ReasoningEffortOption(effort: 'low'),
                ReasoningEffortOption(effort: 'medium'),
                ReasoningEffortOption(effort: 'high'),
              ],
            ),
            'variant': ModelCapabilities(
              reasoning: true,
              thinking: true,
              fast: false,
              reasoningEfforts: [
                ReasoningEffortOption(effort: 'low'),
                ReasoningEffortOption(effort: 'medium'),
                ReasoningEffortOption(effort: 'high'),
              ],
            ),
            'speedster': ModelCapabilities(reasoning: false, fast: true),
            'plain': ModelCapabilities(reasoning: false, fast: false),
          },
        ),
      ],
    );
    ModelPick? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelOptionsProvider.overrideWith(() => _ModelOptionsStub(options)),
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
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showModelPickerSheet(
                    context,
                    ref,
                    initialModel: 'reasoner',
                    initialProvider: 'test',
                    initialReasoningEffort: 'high',
                    initialFastMode: false,
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Fast'), findsNothing);

    // A separate `-fast` model is shown as a toggle on its base family. It
    // must keep the base model's Thinking capability after the id changes.
    await Scrollable.ensureVisible(
      tester.element(find.text('variant')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('variant'));
    await tester.pumpAndSettle();
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);

    await Scrollable.ensureVisible(
      tester.element(find.text('speedster')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('speedster'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Fast'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await Scrollable.ensureVisible(
      tester.element(find.text('plain')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('plain'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Fast'), findsNothing);
    expect(
      find.text('This model has no Thinking or Fast options.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();

    expect(result?.model, 'plain');
    expect(result?.reasoningEffort, 'none');
    expect(result?.fastMode, isFalse);
    expect(result?.fastModeSupported, isFalse);
  });
}
