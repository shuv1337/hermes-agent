import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

void main() {
  test('session runtime state parses model/provider and service tier', () {
    final state = SessionRuntimeState.fromJson({
      'model': 'gpt-5.4',
      'provider': 'openai-codex',
      'reasoning_effort': 'high',
      'service_tier': 'priority',
    });

    expect(state.model, 'gpt-5.4');
    expect(state.provider, 'openai-codex');
    expect(state.reasoningEffort, 'high');
    expect(state.fastMode, isTrue);
  });

  test('session parsing tolerates non-string optional fields', () {
    final session = HermesSession.fromJson({
      'id': 42,
      'title': {'unexpected': true},
      'model': 7,
      'message_count': '3',
    });

    expect(session.id, '42');
    expect(session.title, isNull);
    expect(session.model, '7');
    expect(session.messageCount, 3);
  });

  test('message parsing accepts structured reasoning content', () {
    final message = HermesMessage.fromJson({
      'id': 'm1',
      'role': 'assistant',
      'reasoning': [
        {'text': 'first'},
        {'text': 'second'},
      ],
    });

    expect(message.reasoning, 'first\nsecond');
  });

  test('gateway book ignores malformed selector types', () {
    final book = GatewayBook.fromJson({
      'gateways': [
        {'id': 'gw', 'baseUrl': 'https://gw.example'},
      ],
      'defaultGatewayId': {'not': 'a string'},
    });

    expect(book.resolved?.id, 'gw');
  });

  test('model options preserve server reasoning levels and thinking gate', () {
    final options = ModelOptionsResult.fromJson({
      'providers': [
        {
          'slug': 'openai-codex',
          'name': 'ChatGPT',
          'models': ['gpt-5.6-sol'],
          'capabilities': {
            'gpt-5.6-sol': {
              'reasoning': true,
              'thinking': false,
              'reasoning_efforts': [
                {'effort': 'low', 'description': 'Fast'},
                {'effort': 'ultra', 'description': 'Delegates'},
              ],
              'default_reasoning_effort': 'low',
              'fast': true,
            },
          },
        },
      ],
    });

    final caps = options.providers.single.capsFor('gpt-5.6-sol');
    expect(caps.thinkingSupported, isFalse);
    expect(caps.reasoningEfforts?.map((option) => option.effort), [
      'low',
      'ultra',
    ]);
    expect(caps.reasoningEfforts?.last.description, 'Delegates');
    expect(caps.defaultReasoningEffort, 'low');
    expect(caps.fast, isTrue);
  });
}
