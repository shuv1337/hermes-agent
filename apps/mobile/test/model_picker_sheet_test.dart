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
  testWidgets('a bare {"reasoning": true} capability row renders Thinking and '
      'the full Hermes ladder, and the choices round-trip on confirm', (
    tester,
  ) async {
    // THE shape a stock Hermes 0.20.2 gateway sends. Its `_apply_capabilities`
    // builds one dict per model with nothing but `fast` and `reasoning` — no
    // `thinking` key and no `reasoning_efforts` key, for any provider. Desktop
    // renders Thinking + its hardcoded 7-level ladder from `reasoning` alone
    // against this exact server, so the phone must too. Gating on `thinking`
    // or on a server-published effort list left the user with a lone Fast
    // toggle and no way to set effort at all.
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'openai-codex',
          name: 'ChatGPT',
          models: ['gpt-5.6-terra'],
          capabilities: {
            'gpt-5.6-terra': ModelCapabilities(reasoning: true, fast: true),
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
                    initialModel: 'gpt-5.6-terra',
                    initialProvider: 'openai-codex',
                    initialReasoningEffort: 'medium',
                    initialFastMode: false,
                  );
                },
                child: const Text('Open stock picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open stock picker'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    for (final label in [
      'Minimal',
      'Low',
      'Medium',
      'High',
      'Extra high',
      'Max',
      'Ultra',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Fast'), findsOneWidget);
    expect(
      find.text('This model has no Thinking or Fast options.'),
      findsNothing,
    );

    // Both controls must actually move, and both must survive confirm — the
    // old gating reported `reasoningSupported: false` here, so the chat screen
    // skipped `applySessionReasoning` entirely and the effort never persisted.
    await tester.tap(find.text('Extra high'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).last); // Fast
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();

    expect(result?.model, 'gpt-5.6-terra');
    expect(result?.reasoningSupported, isTrue);
    expect(result?.reasoningEffort, 'xhigh');
    expect(result?.fastModeSupported, isTrue);
    expect(result?.fastMode, isTrue);
  });

  testWidgets('picker falls back to the Hermes ladder when a capability-aware '
      'gateway reports reasoning without a per-model effort list', (
    tester,
  ) async {
    // The exact row `hermes_cli/inventory.py` `_apply_capabilities` emits for
    // `openai-codex` when `get_codex_model_options()` returns None (the Codex
    // catalog was never discovered in the gateway process): `fast`/`reasoning`/
    // `thinking` are stamped on every row, `reasoning_efforts` is absent.
    // The missing effort list uses the compatibility ladder, while the
    // explicit `thinking: false` remains authoritative.
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'openai-codex',
          name: 'ChatGPT',
          models: ['gpt-5.6-terra'],
          capabilities: {
            'gpt-5.6-terra': ModelCapabilities(
              reasoning: true,
              thinking: false,
              fast: true,
            ),
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
                  initialModel: 'gpt-5.6-terra',
                  initialProvider: 'openai-codex',
                  initialReasoningEffort: 'medium',
                  initialFastMode: false,
                ),
                child: const Text('Open codex picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open codex picker'));
    await tester.pumpAndSettle();

    expect(find.text('Effort'), findsOneWidget);
    for (final label in [
      'Minimal',
      'Low',
      'Medium',
      'High',
      'Extra high',
      'Max',
      'Ultra',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Fast'), findsOneWidget);
    expect(
      find.text('This model has no Thinking or Fast options.'),
      findsNothing,
    );
    expect(find.text('Thinking'), findsNothing);
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

    // Server-named levels and the explicit Thinking gate both win.
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

  testWidgets('picker honors an explicitly empty server effort list', (
    tester,
  ) async {
    const options = ModelOptionsResult(
      providers: [
        ModelOptionProvider(
          slug: 'authoritative',
          name: 'Authoritative server',
          models: ['fixed-reasoner'],
          capabilities: {
            'fixed-reasoner': ModelCapabilities(
              reasoning: true,
              thinking: false,
              reasoningEfforts: [],
            ),
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
                  initialModel: 'fixed-reasoner',
                  initialProvider: 'authoritative',
                ),
                child: const Text('Open authoritative picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open authoritative picker'));
    await tester.pumpAndSettle();

    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Minimal'), findsNothing);
    expect(
      find.text('This model has no Thinking or Fast options.'),
      findsOneWidget,
    );
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
