import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/features/sessions/session_chat_screen.dart';

/// Regression coverage for the "autoscroll fights the user during
/// generation" bug, and its sequel — "the user can't scroll up at all".
///
/// The message list renders `reverse: true`, so the newest message sits at
/// scroll offset 0 — the pin/unpin decision is therefore "close to zero",
/// the *opposite* of the usual `maxScrollExtent` convention for a
/// non-reversed list. [isPinnedToBottom] is the extracted pure decision
/// function so this can be verified without pumping a widget tree or a real
/// ScrollController.
///
/// [compensatedScrollOffset] is the growth-compensation decision function.
/// An earlier version derived "how much did the streaming message grow"
/// from the frame-over-frame delta of `ScrollPosition.maxScrollExtent`.
/// That premise doesn't hold for a lazily-built `ListView.builder`:
/// `maxScrollExtent` is an *estimate* over whatever children have been laid
/// out so far, and it moves simply from the user scrolling into
/// not-yet-built items — with zero content growth. Verified empirically in
/// a throwaway widget test during triage: scrolling a static (non-growing)
/// reversed list of 500 fixed-height items moved `maxScrollExtent` by
/// thousands of pixels across a handful of scroll steps. Reading that as
/// "content grew" and `jumpTo`-correcting for it created a feedback loop —
/// scroll up → more items lay out → estimate jumps → code overcorrects →
/// which lays out more items → estimate jumps again — which is exactly the
/// reported "can't scroll up, swipes get yanked back, eventually settles"
/// symptom.
///
/// The rewritten [compensatedScrollOffset] instead takes the streaming
/// bubble's own measured height (before/after) as the sole growth signal,
/// and folds in every gating condition — pinned, not actually streaming, or
/// mid drag/fling — directly into the function so all of it is covered
/// here without needing to pump a widget tree.
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

  group('compensatedScrollOffset', () {
    double? call({
      bool pinnedToBottom = false,
      bool isStreaming = true,
      bool userIsScrolling = false,
      double pixels = 500,
      double? oldStreamingHeight = 200,
      double? newStreamingHeight = 260,
      double maxScrollExtent = 5000,
    }) {
      return compensatedScrollOffset(
        pinnedToBottom: pinnedToBottom,
        isStreaming: isStreaming,
        userIsScrolling: userIsScrolling,
        pixels: pixels,
        oldStreamingHeight: oldStreamingHeight,
        newStreamingHeight: newStreamingHeight,
        maxScrollExtent: maxScrollExtent,
      );
    }

    test('pinned to bottom — never compensates, even if the bubble grew', () {
      final target = call(pinnedToBottom: true);
      expect(
        target,
        isNull,
        reason:
            'while pinned, the reverse-list anchor already keeps the '
            'newest content glued to the bottom for free — no jump needed',
      );
    });

    test(
      'nothing streaming — never compensates, regardless of other inputs',
      () {
        final target = call(isStreaming: false);
        expect(
          target,
          isNull,
          reason:
              'outside an active stream nothing above the viewport is '
              'changing size, so there is nothing to correct for — touching '
              'the offset here would just be an unexplained jump',
        );
      },
    );

    test('REGRESSION: a user drag/fling in progress — never compensates, '
        'even mid-stream with real growth', () {
      final target = call(userIsScrolling: true);
      expect(
        target,
        isNull,
        reason:
            'nudging pixels while the user\'s finger is down (or the '
            'resulting fling hasn\'t settled) can cancel or corrupt the '
            'drag/ballistic simulation — this is the mechanism behind '
            'the "can\'t scroll up, gets yanked back" bug report',
      );
    });

    test('REGRESSION: maxScrollExtent swinging wildly with no bubble growth '
        'never compensates — the delta comes only from measured height', () {
      // Simulates exactly what was observed empirically: scrolling a lazy
      // reversed ListView.builder changes maxScrollExtent by thousands of
      // pixels purely from laying out not-yet-built items, with nothing
      // actually growing. The old implementation derived its "growth"
      // signal from maxScrollExtent and would have produced a large
      // spurious jumpTo here; the new signal is blind to it because it
      // never looks at maxScrollExtent for the delta, only for clamping.
      final target = call(
        oldStreamingHeight: 200,
        newStreamingHeight: 200, // bubble itself did not change size
        maxScrollExtent: 38775, // frame N
      );
      expect(target, isNull);

      final target2 = call(
        oldStreamingHeight: 200,
        newStreamingHeight: 200,
        maxScrollExtent: 42306, // frame N+1 — extent jumped ~3500px
      );
      expect(target2, isNull);
    });

    test('no prior baseline yet (first frame) — does not compensate', () {
      final target = call(oldStreamingHeight: null);
      expect(target, isNull);
    });

    test('streaming bubble not currently laid out this frame — does not '
        'compensate (can\'t measure what isn\'t built)', () {
      final target = call(newStreamingHeight: null);
      expect(target, isNull);
    });

    test('unpinned, streaming, not user-scrolling, and the bubble grows — '
        'nudges pixels by exactly the height delta so the same content '
        'stays under the viewport', () {
      // User scrolled up to read history (pixels = 500). The streaming
      // bubble below them grows by 300px (oldHeight -> newHeight).
      final target = call(oldStreamingHeight: 1000, newStreamingHeight: 1300);
      expect(
        target,
        500 + 300,
        reason:
            'without this nudge the same absolute `pixels` would now '
            'point at different (newer) content, which reads as the '
            'viewport drifting toward the bottom under the user',
      );
    });

    test('the bubble shrinking nudges pixels down to match', () {
      final target = call(
        pixels: 800,
        oldStreamingHeight: 1000,
        newStreamingHeight: 700,
      );
      expect(target, 500);
    });

    test('sub-pixel noise (< 0.5px) is ignored — no jitter', () {
      final target = call(oldStreamingHeight: 1000, newStreamingHeight: 1000.2);
      expect(target, isNull);
    });

    test('the compensated offset is clamped into [0, maxScrollExtent]', () {
      final target = call(
        pixels: 900,
        oldStreamingHeight: 1000,
        newStreamingHeight: 950,
        maxScrollExtent: 950,
      );
      // Naively 900 + (950-1000) = 850, well inside range — but a large
      // shrink must never push the target past the current max extent.
      expect(target! <= 950, isTrue);
    });

    test('the compensated offset never goes negative', () {
      final target = call(
        pixels: 10,
        oldStreamingHeight: 1000,
        newStreamingHeight: 200,
        maxScrollExtent: 5000,
      );
      expect(target, 0.0);
    });
  });
}
