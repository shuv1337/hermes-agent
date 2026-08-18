import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/sync/single_flight.dart';

void main() {
  group('SingleFlight', () {
    test('concurrent calls collapse into one underlying call, both get the '
        'result', () async {
      var calls = 0;
      final completer = Completer<int>();
      final flight = SingleFlight<int>();

      Future<int> action() {
        calls++;
        return completer.future;
      }

      // Both calls start before either resolves — classic startup-race shape
      // (e.g. sessionsProvider.build() + GatewayShell.softRefresh() firing
      // within the same tick).
      final f1 = flight.run(action);
      final f2 = flight.run(action);

      expect(calls, 1, reason: 'second caller must not start a new request');
      expect(identical(f1, f2), isTrue);

      completer.complete(42);
      expect(await f1, 42);
      expect(await f2, 42);
      expect(calls, 1);
    });

    test('after completion, a call within the TTL reuses the cached result '
        'without re-invoking the action', () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1, 12);
      final flight = SingleFlight<int>(
        ttl: const Duration(seconds: 4),
        now: () => now,
      );

      Future<int> action() async {
        calls++;
        return calls;
      }

      expect(await flight.run(action), 1);
      expect(calls, 1);

      // 1s later — well inside the 4s TTL — must not hit the network again.
      now = now.add(const Duration(seconds: 1));
      expect(await flight.run(action), 1);
      expect(calls, 1);
    });

    test('after TTL expiry, the next call goes to the network again', () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1, 12);
      final flight = SingleFlight<int>(
        ttl: const Duration(seconds: 4),
        now: () => now,
      );

      Future<int> action() async {
        calls++;
        return calls;
      }

      expect(await flight.run(action), 1);

      // Past the TTL window — must issue a fresh call.
      now = now.add(const Duration(seconds: 5));
      expect(await flight.run(action), 2);
      expect(calls, 2);
    });

    test('bypassTtl forces a fresh call even when a cached result is still '
        'within the TTL window', () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1, 12);
      final flight = SingleFlight<int>(
        ttl: const Duration(seconds: 4),
        now: () => now,
      );

      Future<int> action() async {
        calls++;
        return calls;
      }

      expect(await flight.run(action), 1);

      now = now.add(const Duration(seconds: 1));
      // Explicit user-initiated refresh (pull-to-refresh style) — must hit
      // the network even though the cached result is fresh.
      expect(await flight.run(action, bypassTtl: true), 2);
      expect(calls, 2);
    });

    test('bypassTtl still joins an already in-flight call instead of firing '
        'a second concurrent request', () async {
      var calls = 0;
      final completer = Completer<int>();
      final flight = SingleFlight<int>();

      Future<int> action() {
        calls++;
        return completer.future;
      }

      final f1 = flight.run(action);
      // A "pull-to-refresh" arrives while the first pull is still running —
      // it must share the in-flight future, not start a second request.
      final f2 = flight.run(action, bypassTtl: true);

      expect(calls, 1);
      completer.complete(7);
      expect(await f1, 7);
      expect(await f2, 7);
    });

    test('a failed flight is not cached — the next call retries', () async {
      var calls = 0;
      final flight = SingleFlight<int>();

      Future<int> action() async {
        calls++;
        if (calls == 1) {
          throw StateError('network error');
        }
        return 99;
      }

      await expectLater(flight.run(action), throwsA(isA<StateError>()));
      expect(calls, 1);

      // Immediately after the failure — no TTL caching of the error, and no
      // stale in-flight future left behind.
      expect(await flight.run(action), 99);
      expect(calls, 2);
    });

    test('isInFlight reflects whether a call is currently running', () async {
      final completer = Completer<int>();
      final flight = SingleFlight<int>();
      expect(flight.isInFlight, isFalse);

      final future = flight.run(() => completer.future);
      expect(flight.isInFlight, isTrue);

      completer.complete(1);
      await future;
      expect(flight.isInFlight, isFalse);
    });

    test('invalidate drops a cached result so the next call hits the '
        'network again', () async {
      var calls = 0;
      final flight = SingleFlight<int>(ttl: const Duration(seconds: 30));

      Future<int> action() async {
        calls++;
        return calls;
      }

      expect(await flight.run(action), 1);
      flight.invalidate();
      expect(await flight.run(action), 2);
      expect(calls, 2);
    });
  });
}
