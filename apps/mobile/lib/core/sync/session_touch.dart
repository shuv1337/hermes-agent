/// Fired when the gateway cache should be reflected in the UI.
class SessionTouch {
  const SessionTouch({this.sessionId, this.reason = 'event'});

  /// Live or stored session id, if the event was session-scoped.
  final String? sessionId;

  /// e.g. `event`, `poll`, `connect`, `complete`
  final String reason;
}
