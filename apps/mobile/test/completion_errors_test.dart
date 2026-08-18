import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/sync/completion_errors.dart';

HermesMessage message(
  String id,
  String role,
  String content, {
  String? finishReason,
}) => HermesMessage(
  id: id,
  sessionId: 'session-1',
  role: role,
  content: content,
  finishReason: finishReason,
);

void main() {
  test('terminal local error survives a transcript sync with no reply', () {
    final user = message('user-1', 'user', 'hello');
    final error = message(
      'local-error-1',
      'assistant',
      'HTTP 404: Model not found',
      finishReason: 'error',
    );

    final merged = preserveTerminalErrorAfterSync([user], [user, error]);

    expect(merged, hasLength(2));
    expect(merged.last.id, 'local-error-1');
    expect(merged.last.finishReason, 'error');
  });

  test('successful remote reply supersedes an old terminal error', () {
    final user = message('user-1', 'user', 'hello');
    final error = message(
      'local-error-1',
      'assistant',
      'HTTP 404: Model not found',
      finishReason: 'error',
    );
    final reply = message('assistant-2', 'assistant', 'Success');

    final merged = preserveTerminalErrorAfterSync([user, reply], [user, error]);

    expect(merged, [user, reply]);
  });

  test('already-synced error is not duplicated', () {
    final user = message('user-1', 'user', 'hello');
    final error = message(
      'error-1',
      'assistant',
      'HTTP 429: Usage limit reached',
      finishReason: 'error',
    );

    final merged = preserveTerminalErrorAfterSync([user, error], [user, error]);

    expect(merged, hasLength(2));
  });
}
