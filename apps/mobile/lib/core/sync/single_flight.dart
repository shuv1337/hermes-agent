import 'dart:async';

/// Coalesces concurrent + rapid-fire calls to the same expensive operation
/// (typically a network pull) behind one shared [Future].
///
/// Two mechanisms combine to prevent redundant work:
///
/// - **In-flight sharing**: if [run] is called while a previous call's
///   [Future] has not completed yet, every caller gets that same Future
///   instead of starting a second request.
/// - **Short TTL cache**: once a call *succeeds*, the resolved value is
///   reused for [ttl]. This matters at app cold-start, where several
///   Riverpod providers / screens each kick their own "initial sync" a few
///   milliseconds apart — after the network round trip lands, the next
///   trigger arrives *after* the in-flight future already completed, so
///   in-flight sharing alone would miss it. The TTL catches that case.
///
/// A **failed** flight is never cached — the next call always retries
/// against the network rather than replaying a stale error.
///
/// Callers that need authoritative fresh data (explicit pull-to-refresh, a
/// picker's "refresh" affordance, …) pass `bypassTtl: true`. That skips the
/// recently-completed-result shortcut and issues a new request, but it
/// still joins an already in-flight call rather than firing a redundant
/// concurrent request — an explicit refresh should not pile a second
/// request on top of one that is already running.
class SingleFlight<T> {
  SingleFlight({this.ttl = const Duration(seconds: 4), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;

  Future<T>? _inflight;
  T? _cachedValue;
  DateTime? _completedAt;

  /// True while a call started by [run] has not resolved yet.
  bool get isInFlight => _inflight != null;

  /// Run [action], coalescing with any in-flight or recently-completed call.
  ///
  /// - If a call is already in flight, its [Future] is returned as-is
  ///   (regardless of [bypassTtl]).
  /// - Else, if a prior call succeeded within [ttl] and [bypassTtl] is
  ///   `false`, the cached value is returned immediately without invoking
  ///   [action].
  /// - Otherwise [action] runs. A successful result is cached for [ttl]; a
  ///   failure is never cached.
  Future<T> run(Future<T> Function() action, {bool bypassTtl = false}) {
    final inflight = _inflight;
    if (inflight != null) return inflight;

    if (!bypassTtl) {
      final completedAt = _completedAt;
      if (completedAt != null && _now().difference(completedAt) < ttl) {
        return Future.value(_cachedValue as T);
      }
    }

    final future = action();
    _inflight = future;
    future.then(
      (value) {
        _cachedValue = value;
        _completedAt = _now();
      },
      onError: (Object _, StackTrace _) {
        // Failed flights are not cached — the next call retries.
        _cachedValue = null;
        _completedAt = null;
      },
    ).whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
      }
    });
    return future;
  }

  /// Drop any cached completed result. Does not cancel an in-flight call.
  void invalidate() {
    _cachedValue = null;
    _completedAt = null;
  }
}
