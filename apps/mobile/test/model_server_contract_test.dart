import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/db/app_database.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/network/gateway_ws_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/sync/gateway_realtime.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';
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

class _RecordingRealtime extends GatewayRealtime {
  _RecordingRealtime(SessionSyncRepository repository)
    : super(
        profile: const ConnectionProfile(
          id: 'mock-gateway',
          baseUrl: 'https://gateway.test',
        ),
        sessionSync: repository,
      );

  final calls = <({String method, Map<String, dynamic> params})>[];

  @override
  bool get isLive => true;

  @override
  Stream<GatewayWsEvent> get events => const Stream.empty();

  @override
  Future<bool> ensureLive({bool force = false}) async => true;

  @override
  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? params,
    Duration? timeout,
  ]) async {
    calls.add((method: method, params: {...?params}));
    if (method == 'session.create') {
      return {
        'session_id': 'live-session',
        'stored_session_id': 'stored-session',
        'info': {
          'model': params?['model'],
          'provider': params?['provider'],
          'reasoning_effort': params?['reasoning_effort'],
          'fast': params?['fast'] == true,
        },
      };
    }
    return {'ok': true};
  }
}

class _ModelCase {
  const _ModelCase({
    required this.provider,
    required this.model,
    required this.efforts,
    required this.defaultEffort,
    required this.selectedEffort,
    required this.thinking,
    required this.fast,
    this.reasoning = true,
  });

  final String provider;
  final String model;
  final List<String> efforts;
  final String? defaultEffort;
  final String selectedEffort;
  final bool thinking;
  final bool fast;
  final bool reasoning;
}

const _cases = <_ModelCase>[
  _ModelCase(
    provider: 'nous',
    model: 'anthropic/claude-fable-5',
    efforts: ['max', 'xhigh', 'high', 'medium', 'low'],
    defaultEffort: 'medium',
    selectedEffort: 'high',
    thinking: false,
    fast: false,
  ),
  _ModelCase(
    provider: 'nous',
    model: 'anthropic/claude-opus-4.8',
    efforts: ['max', 'xhigh', 'high', 'medium', 'low'],
    defaultEffort: 'medium',
    selectedEffort: 'none',
    thinking: true,
    fast: false,
  ),
  _ModelCase(
    provider: 'nous',
    model: 'anthropic/claude-sonnet-5',
    efforts: ['max', 'xhigh', 'high', 'medium', 'low'],
    defaultEffort: 'medium',
    selectedEffort: 'xhigh',
    thinking: true,
    fast: false,
  ),
  _ModelCase(
    provider: 'nous',
    model: 'anthropic/claude-haiku-4.5',
    efforts: [],
    defaultEffort: null,
    selectedEffort: 'none',
    thinking: false,
    fast: false,
    reasoning: false,
  ),
  _ModelCase(
    provider: 'nous',
    model: 'openai/gpt-5.6-sol',
    efforts: ['max', 'xhigh', 'high', 'medium', 'low'],
    defaultEffort: 'medium',
    selectedEffort: 'low',
    thinking: true,
    fast: true,
  ),
  _ModelCase(
    provider: 'openai-codex',
    model: 'gpt-5.6-sol',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
    defaultEffort: 'low',
    selectedEffort: 'ultra',
    thinking: false,
    fast: true,
  ),
  _ModelCase(
    provider: 'openai-codex',
    model: 'gpt-5.6-terra',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
    defaultEffort: 'medium',
    selectedEffort: 'medium',
    thinking: false,
    fast: true,
  ),
  _ModelCase(
    provider: 'openai-codex',
    model: 'gpt-5.6-luna',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
    defaultEffort: 'medium',
    selectedEffort: 'low',
    thinking: false,
    fast: true,
  ),
  _ModelCase(
    provider: 'xai-oauth',
    model: 'grok-4.5',
    efforts: ['low', 'medium', 'high'],
    defaultEffort: null,
    selectedEffort: 'high',
    thinking: false,
    fast: false,
  ),
];

Map<String, dynamic> _mockServerPayload() {
  final grouped = <String, List<_ModelCase>>{};
  for (final modelCase in _cases) {
    grouped.putIfAbsent(modelCase.provider, () => []).add(modelCase);
  }
  return {
    'providers': [
      for (final entry in grouped.entries)
        {
          'slug': entry.key,
          'name': entry.key,
          'models': [for (final modelCase in entry.value) modelCase.model],
          'capabilities': {
            for (final modelCase in entry.value)
              modelCase.model: {
                'reasoning': modelCase.reasoning,
                'thinking': modelCase.thinking,
                'fast': modelCase.fast,
                'reasoning_efforts': [
                  for (final effort in modelCase.efforts) {'effort': effort},
                ],
                if (modelCase.defaultEffort != null)
                  'default_reasoning_effort': modelCase.defaultEffort,
              },
          },
        },
    ],
  };
}

void main() {
  final options = ModelOptionsResult.fromJson(_mockServerPayload());

  test('mocked server capabilities are preserved exactly for every model', () {
    for (final modelCase in _cases) {
      final provider = options.providers.singleWhere(
        (candidate) => candidate.slug == modelCase.provider,
      );
      final capabilities = provider.capsFor(modelCase.model);
      expect(
        capabilities.reasoningEfforts?.map((option) => option.effort).toList(),
        modelCase.efforts,
        reason: modelCase.model,
      );
      expect(
        capabilities.defaultReasoningEffort,
        modelCase.defaultEffort,
        reason: modelCase.model,
      );
      expect(
        capabilities.reasoning,
        modelCase.reasoning,
        reason: modelCase.model,
      );
      expect(
        capabilities.thinkingSupported,
        modelCase.thinking,
        reason: modelCase.model,
      );
      expect(capabilities.fast, modelCase.fast, reason: modelCase.model);
    }
  });

  for (final modelCase in _cases) {
    testWidgets(
      'server contract ${modelCase.provider}/${modelCase.model} reaches gateway RPCs unchanged',
      (tester) async {
        ModelPick? pick;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              modelOptionsProvider.overrideWith(
                () => _ModelOptionsStub(options),
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
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      pick = await showModelPickerSheet(
                        context,
                        ref,
                        initialModel: modelCase.model,
                        initialProvider: modelCase.provider,
                        initialReasoningEffort: modelCase.selectedEffort,
                        initialFastMode: modelCase.fast,
                      );
                    },
                    child: const Text('Open contract picker'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open contract picker'));
        await tester.pumpAndSettle();

        expect(
          find.text('Thinking'),
          modelCase.thinking ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Effort'),
          modelCase.reasoning &&
                  modelCase.efforts.isNotEmpty &&
                  modelCase.selectedEffort != 'none'
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.text('Fast'),
          modelCase.fast ? findsOneWidget : findsNothing,
        );

        await tester.tap(find.text('Use this model'));
        await tester.pumpAndSettle();

        expect(pick?.model, modelCase.model);
        expect(pick?.provider, modelCase.provider);
        expect(pick?.reasoningEffort, modelCase.selectedEffort);
        expect(pick?.reasoningSupported, modelCase.reasoning);
        expect(pick?.fastMode, modelCase.fast);
        expect(pick?.fastModeSupported, modelCase.fast);

        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final repository = SessionSyncRepository(
          gatewayId: 'mock-gateway',
          db: db,
          api: null,
        );
        final realtime = _RecordingRealtime(repository);
        repository.bindRealtime(realtime);
        addTearDown(() async {
          await realtime.dispose();
          await db.close();
        });

        await repository.createSession(
          title: 'Contract test',
          model: pick!.model,
          provider: pick!.provider,
          reasoningEffort: pick!.reasoningEffort,
          fastMode: pick!.fastMode,
        );

        final create = realtime.calls.singleWhere(
          (call) => call.method == 'session.create',
        );
        expect(create.params['model'], modelCase.model);
        expect(create.params['provider'], modelCase.provider);
        expect(create.params['reasoning_effort'], modelCase.selectedEffort);
        if (modelCase.fast) {
          expect(create.params['fast'], isTrue);
        } else {
          expect(create.params.containsKey('fast'), isFalse);
        }

        // A real turn re-pins these same session-scoped controls immediately
        // before prompt.submit. Validate the actual RPC contract directly;
        // prompt.submit itself carries only session_id + text.
        realtime.calls.clear();
        await repository.applySessionModel(
          sessionId: 'stored-session',
          model: pick!.model,
          provider: pick!.provider,
        );
        await repository.applySessionReasoning(
          sessionId: 'stored-session',
          effort: pick!.reasoningEffort!,
        );
        await repository.applySessionFast(
          sessionId: 'stored-session',
          enabled: pick!.fastMode!,
        );

        final configCalls = realtime.calls
            .where((call) => call.method == 'config.set')
            .toList();
        expect(configCalls, hasLength(3));
        expect(configCalls[0].params, {
          'session_id': 'live-session',
          'key': 'model',
          'value':
              '${modelCase.model} --provider ${modelCase.provider} --session',
        });
        expect(configCalls[1].params, {
          'session_id': 'live-session',
          'key': 'reasoning',
          'value': modelCase.selectedEffort,
        });
        expect(configCalls[2].params, {
          'session_id': 'live-session',
          'key': 'fast',
          'value': modelCase.fast ? 'fast' : 'normal',
        });
      },
    );
  }
}
