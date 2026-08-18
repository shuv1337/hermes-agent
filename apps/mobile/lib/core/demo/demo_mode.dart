/// Small constants + a process-lifetime holder for demo mode.
///
/// This is the seam wave 2 (connect-screen + provider wiring) is built on:
/// - [demoGatewayHost] is the reserved hostname a reviewer types into the
///   "gateway host" field instead of a real server address.
/// - [demoProfileId] lets a saved `ConnectionProfile` be flagged as the
///   sandbox without any storage schema migration.
/// - [DemoGatewayHolder] owns the one [DemoGatewayServer] instance for the
///   process and hands out its (ephemeral, launch-to-launch-varying) base
///   URL.
///
/// No Riverpod provider lives here on purpose — wave 2 owns provider wiring
/// and can wrap [DemoGatewayHolder.instance] in whatever provider shape it
/// needs. Everything below is plain Dart so it's trivial to wrap.
library;

import 'package:hermes_mobile/core/demo/demo_gateway_server.dart';

/// Re-exported so callers only need `demo_mode.dart` — `demo_gateway_server.dart`
/// is the single source of truth (see its doc comment) and can't import this
/// file back without a cycle.
export 'package:hermes_mobile/core/demo/demo_gateway_server.dart'
    show demoUsername, demoPassword;

/// Reserved gateway hostname that boots the sandbox instead of dialing out.
///
/// The connect screen (wave 2) must intercept this host **before** any DNS
/// lookup or network call happens — `demo.hermes.go` is not expected to
/// resolve, and never should need to.
const demoGatewayHost = 'demo.hermes.go';

/// True when [raw] — typed into the gateway-host field, with or without a
/// scheme or port — resolves to [demoGatewayHost].
///
/// Case-insensitive and scheme-agnostic: `demo.hermes.go`,
/// `https://demo.hermes.go`, and `DEMO.HERMES.GO:9119` all match.
bool isDemoGatewayUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  // A bare host (no `scheme://`) parses with an empty `Uri.host`, so give it
  // one before parsing rather than trying to special-case host-only input.
  final candidate = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(candidate);
  final host = uri?.host.toLowerCase() ?? '';
  return host == demoGatewayHost;
}

/// Sentinel id wave 2 stamps on the saved `ConnectionProfile` for the demo
/// sandbox, so the rest of the app can special-case it (e.g. "Exit demo
/// mode" in Settings) without a persisted-schema field.
const demoProfileId = 'demo';

/// True when [id] is the demo profile's sentinel id.
bool isDemoProfileId(String id) => id == demoProfileId;

/// Owns the single [DemoGatewayServer] instance for the process.
///
/// The server binds an **ephemeral** port, so it picks a different port on
/// every launch — [ensureRunning] is safe (and cheap) to call repeatedly;
/// wave 2 calls it both at app boot (when the active profile is the demo
/// profile) and from the connect screen, and must rewrite the profile's
/// stored `baseUrl` with whatever URI comes back each time.
class DemoGatewayHolder {
  DemoGatewayHolder._();

  static final DemoGatewayHolder instance = DemoGatewayHolder._();

  DemoGatewayServer? _server;
  Uri? _baseUri;

  bool get isRunning => _server?.isRunning ?? false;
  Uri? get baseUri => _baseUri;

  /// Starts the demo gateway if it isn't already running, and returns its
  /// base URL (`http://127.0.0.1:<port>`). Calling this while already
  /// running is a cheap no-op that returns the existing URL.
  ///
  /// The scripted turn runs at its real ~8-15s pace by default. That is short
  /// enough that UI automation (tap, swipe, screenshot round-trips) routinely
  /// misses the streaming window entirely, which makes streaming-only
  /// behaviour — scroll anchoring above all — effectively unobservable in a
  /// simulator. `--dart-define=DEMO_SPEED=4` stretches every scripted delay so
  /// a turn can actually be watched. Release builds never pass it, so the
  /// shipped pace is unchanged.
  static const _speedOverride = String.fromEnvironment('DEMO_SPEED');

  Future<Uri> ensureRunning() async {
    final factor = double.tryParse(_speedOverride) ?? 1.0;
    final server = _server ??= DemoGatewayServer(
      demoSpeedFactor: factor > 0 ? factor : 1.0,
    );
    final uri = await server.start();
    _baseUri = uri;
    return uri;
  }

  /// Stops the demo gateway, if running. The next [ensureRunning] call boots
  /// a fresh instance (and a fresh, differently-ported workspace).
  Future<void> shutdown() async {
    final server = _server;
    if (server == null) return;
    await server.stop();
    _server = null;
    _baseUri = null;
  }
}
