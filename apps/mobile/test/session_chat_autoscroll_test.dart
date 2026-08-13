import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/features/sessions/session_chat_screen.dart';

/// Regression coverage for "the transcript drifts / jitters under the user
/// while a reply streams in".
///
/// History, because it explains why the fix lives where it does. The message
/// list renders `reverse: true`, so the newest message is index 0 at scroll
/// offset 0 and older messages occupy increasing offsets — pin detection is
/// therefore "close to zero", the *opposite* of the usual `maxScrollExtent`
/// convention.
///
///  * Attempt 1 compensated the user's `pixels` by the frame-over-frame
///    delta of `ScrollPosition.maxScrollExtent`. On a lazily-built
///    `ListView.builder` that value is an *estimate* over whatever children
///    have been laid out so far and moves purely from scrolling into
///    not-yet-built items. Scrolling up fed the compensation and the list
///    became nearly unscrollable.
///  * Attempt 2 fixed the *signal* — measuring the streaming bubble's real
///    `RenderBox` height — but kept the shape: correct the offset from a
///    post-frame callback. That is structurally jittery. Every token
///    composites one frame with the content in the wrong place and then
///    `jumpTo`s it back, so at streaming rates the text visibly glitches up
///    and down. No better delta measurement can fix a reactive correction.
///  * Attempt 3 sidestepped the jitter by *freezing* the rendered transcript
///    while the user was scrolled up mid-stream, buffering deltas until they
///    re-pinned. No jitter, but the transcript stopped updating while you
///    read it — worse than mainstream chat apps.
///
/// The current design instead adopts `scrollview_observer`'s
/// `ChatScrollObserver` / `ChatObserverClampingScrollPhysics`, which override
/// `ScrollPhysics.adjustPositionForNewDimensions` — called by
/// `ScrollPosition.applyContentDimensions` *during layout* — so a corrected
/// scroll offset lands in the same frame the content grew. Nothing wrong is
/// ever painted, and the transcript always renders the live message list; see
/// `SessionChatScreenState._chatObserver` and its `standby()` call sites in
/// `session_chat_screen.dart` for the wiring. That machinery is the
/// package's, not this app's, so it is exercised by `flutter test`'s widget
/// tests / manual verification rather than a pure-function unit test here.
///
/// What remains as this screen's *own* pure decision surface — and what this
/// file covers — is [isPinnedToBottom] (pin/unpin threshold for the
/// jump-to-latest affordance) and [isUnansweredUserAt] (the "No response
/// yet" + Resend/Edit chip logic).
void main() {
  group('isPinnedToBottom', () {
    test('exactly at the newest-message anchor (offset 0) is pinned', () {
      expect(isPinnedToBottom(0), isTrue);
    });

    test('within the small tolerance band still counts as pinned', () {
      expect(isPinnedToBottom(kAutoscrollPinThresholdPx), isTrue);
      expect(isPinnedToBottom(kAutoscrollPinThresholdPx - 1), isTrue);
    });

    test('past the tolerance — user has deliberately scrolled up — unpins', () {
      expect(isPinnedToBottom(kAutoscrollPinThresholdPx + 1), isFalse);
    });

    test('far up in a long, generated message stays unpinned', () {
      expect(isPinnedToBottom(4200), isFalse);
    });

    test('a custom threshold is honored', () {
      expect(isPinnedToBottom(50, threshold: 40), isFalse);
      expect(isPinnedToBottom(30, threshold: 40), isTrue);
    });
  });

  group('isUnansweredUserAt', () {
    HermesMessage user(String id, {String? displayKind}) => HermesMessage(
      id: id,
      sessionId: 's1',
      role: 'user',
      content: 'q',
      displayKind: displayKind,
    );
    HermesMessage assistant(
      String id,
      String content, {
      String? finishReason,
    }) => HermesMessage(
      id: id,
      sessionId: 's1',
      role: 'assistant',
      content: content,
      finishReason: finishReason,
    );

    test('out-of-range and non-user indices are false', () {
      final messages = [user('u1'), assistant('a1', 'hi')];
      expect(isUnansweredUserAt(messages, -1, sending: false), isFalse);
      expect(isUnansweredUserAt(messages, 9, sending: false), isFalse);
      expect(isUnansweredUserAt(messages, 1, sending: false), isFalse);
    });

    test('answered turn is not unanswered', () {
      final messages = [user('u1'), assistant('a1', 'here you go')];
      expect(isUnansweredUserAt(messages, 0, sending: false), isFalse);
    });

    test(
      'trailing user turn with nothing after it is unanswered when idle',
      () {
        expect(isUnansweredUserAt([user('u1')], 0, sending: false), isTrue);
      },
    );

    test(
      '…but NOT while the turn is in flight — it is waiting, not failed',
      () {
        expect(isUnansweredUserAt([user('u1')], 0, sending: true), isFalse);
      },
    );

    test('REGRESSION: `sending` alone flips the answer — callers must pass '
        'the flag that matches the state their render pass used', () {
      // This is a height change (a "No response yet" label plus Resend/Edit
      // chips appear). The function stays pure/parameterized specifically so
      // callers can't accidentally derive it from stale state.
      final messages = [user('u1')];
      expect(
        isUnansweredUserAt(messages, 0, sending: true),
        isNot(isUnansweredUserAt(messages, 0, sending: false)),
      );
    });

    test('an earlier turn is still judged normally while a later one is in '
        'flight', () {
      final messages = [user('u1'), user('u2')];
      expect(isUnansweredUserAt(messages, 0, sending: true), isTrue);
      expect(isUnansweredUserAt(messages, 1, sending: true), isFalse);
    });

    test('an error reply counts as unanswered', () {
      final messages = [
        user('u1'),
        assistant('a1', 'nope', finishReason: 'error'),
      ];
      expect(isUnansweredUserAt(messages, 0, sending: false), isTrue);
    });

    test('empty assistant rows are skipped, tool/system rows are not '
        'turn boundaries', () {
      final messages = [
        user('u1'),
        assistant('a0', ''),
        HermesMessage(
          id: 't1',
          sessionId: 's1',
          role: 'tool',
          content: 'ran',
          toolName: 'bash',
        ),
        HermesMessage(id: 's2', sessionId: 's1', role: 'system', content: 'x'),
        assistant('a1', 'the real reply'),
      ];
      expect(isUnansweredUserAt(messages, 0, sending: false), isFalse);
    });

    test('a synthetic user-role marker is neither a turn nor a boundary', () {
      final marker = user('m1', displayKind: 'model_switch');
      expect(isUnansweredUserAt([marker], 0, sending: false), isFalse);
      final messages = [user('u1'), marker, assistant('a1', 'reply')];
      expect(isUnansweredUserAt(messages, 0, sending: false), isFalse);
    });
  });
}
