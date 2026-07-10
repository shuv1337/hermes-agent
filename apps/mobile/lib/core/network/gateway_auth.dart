import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/network/secure_cookie_storage.dart';

/// Desktop-parity remote gateway auth.
///
/// Flow (mirrors apps/desktop/electron/main.cjs + hermes_cli/dashboard_auth):
/// 1. GET  /api/status              → auth_required?
/// 2. GET  /api/auth/providers      → password vs OAuth providers
/// 3. POST /auth/password-login     → Set-Cookie (hermes_session_at / _rt)
/// 4. POST /api/auth/ws-ticket      → single-use ticket for /api/ws?ticket=
///
/// No API_SERVER_KEY. Credentials are username/password against a
/// `supports_password` provider; the session lives in cookies afterward.
class GatewayAuthClient {
  GatewayAuthClient({required this.baseUrl, CookieJar? cookieJar, Dio? dio})
    : _jar = cookieJar ?? CookieJar(),
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalize(baseUrl),
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json'},
              // Password login returns Set-Cookie; follow redirects carefully.
              followRedirects: false,
              validateStatus: (s) => s != null && s < 500,
            ),
          ) {
    this.dio.interceptors.add(CookieManager(_jar));
  }

  final String baseUrl;
  final Dio dio;
  final CookieJar _jar;

  CookieJar get cookieJar => _jar;

  static String _normalize(String raw) {
    var v = raw.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// Persistable cookie jar backed by Keychain / EncryptedSharedPreferences.
  ///
  /// The legacy file store is migration-only. Its contents are moved into
  /// secure storage on first read so upgrades preserve existing sessions.
  ///
  /// [ignoreExpires] is true so an expired access-token cookie is still sent
  /// with the refresh token — server middleware then rotates transparently
  /// (same as Desktop). If we drop expired AT cookies, some hosts only see a
  /// bare RT and still 401 if refresh is not triggered the same way.
  static Future<PersistCookieJar> persistentJar(String gatewayId) async {
    final root = await getApplicationSupportDirectory();
    final safe = gatewayId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final dir = Directory('${root.path}/gateway_cookies/$safe');
    await dir.create(recursive: true);
    final legacy = FileStorage(dir.path);
    return PersistCookieJar(
      ignoreExpires: true,
      storage: SecureCookieStorage(
        namespace: safe,
        secureStorage: ConnectionStore.durableSecureStorage(),
        legacyStorage: legacy,
      ),
    );
  }

  /// Validate a gateway base URL before any request is attempted.
  ///
  /// HTTPS is always allowed. Plain HTTP is allowed for loopback and for
  /// private/trusted network space (LAN, VPN mesh, mDNS) because that
  /// traffic never leaves the user's own network — VPN mesh traffic (e.g.
  /// Tailscale/WireGuard) is already encrypted at the tunnel layer. Plain
  /// HTTP to ordinary public hosts remains blocked to protect agent
  /// credentials.
  static String? validateBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return 'Enter a complete gateway URL.';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Use https:// (or http:// for a private network / VPN).';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'Do not put credentials in the gateway URL.';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'Gateway URLs cannot include a query or fragment.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'Gateway URLs cannot include a path.';
    }
    final host = _stripBrackets(uri.host.toLowerCase());
    if (scheme != 'https' &&
        !_isLoopbackHost(host) &&
        !_isPrivateNetworkHost(host)) {
      return 'Remote gateways require HTTPS to protect agent credentials.';
    }
    return null;
  }

  /// True when [raw] parses as a plain `http://` URL pointed at an allowed
  /// non-loopback private/VPN host (LAN, Tailscale, mDNS, CGNAT). Used by
  /// the UI to decide whether to show a non-blocking "unencrypted" hint;
  /// loopback and https:// never need it.
  static bool isUnencryptedPrivateNetworkUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return false;
    }
    if (uri.scheme.toLowerCase() != 'http') return false;
    final host = _stripBrackets(uri.host.toLowerCase());
    if (_isLoopbackHost(host)) return false;
    return _isPrivateNetworkHost(host);
  }

  static String _stripBrackets(String host) =>
      host.replaceAll('[', '').replaceAll(']', '');

  static bool _isLoopbackHost(String host) {
    if (host == 'localhost' || host == '::1') return true;
    final v4 = _parseIPv4(host);
    return v4 != null && v4[0] == 127;
  }

  /// RFC1918 private ranges, link-local, CGNAT (Tailscale tailnet IPs),
  /// mDNS `.local` hostnames, and Tailscale MagicDNS `.ts.net` hostnames.
  /// Does not include loopback — see [_isLoopbackHost].
  static bool _isPrivateNetworkHost(String host) {
    if (host.endsWith('.local') || host.endsWith('.ts.net')) return true;
    final v4 = _parseIPv4(host);
    if (v4 != null) {
      final a = v4[0], b = v4[1];
      if (a == 10) return true; // 10.0.0.0/8
      if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
      if (a == 192 && b == 168) return true; // 192.168.0.0/16
      if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
      if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
      return false;
    }
    // IPv6 unique local fc00::/7 — first byte 0xfc or 0xfd. Anything else
    // (including other IPv6) is treated as public/unrecognized.
    if (host.contains(':') &&
        (host.startsWith('fc') || host.startsWith('fd'))) {
      return true;
    }
    return false;
  }

  /// Parses a dotted-quad IPv4 literal into 4 numeric octets (no substring
  /// matching), or null if [host] is not a valid IPv4 address.
  static List<int>? _parseIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      if (!RegExp(r'^\d+$').hasMatch(part)) return null;
      final n = int.parse(part);
      if (n > 255) return null;
      octets.add(n);
    }
    return octets;
  }

  /// Public probe — no credentials (Desktop probeRemoteAuthMode).
  static Future<GatewayAuthProbe> probe(String baseUrl) async {
    final base = _normalize(baseUrl);
    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json'},
      ),
    );

    Map<String, dynamic>? status;
    try {
      final res = await dio.get<Map<String, dynamic>>('/api/status');
      status = res.data;
    } catch (e) {
      return GatewayAuthProbe(
        baseUrl: base,
        reachable: false,
        authMode: GatewayAuthMode.unknown,
        error: e.toString(),
      );
    }

    final authRequired = status?['auth_required'] == true;
    final providers = <GatewayAuthProvider>[];

    if (authRequired) {
      try {
        final res = await dio.get<Map<String, dynamic>>('/api/auth/providers');
        final raw = res.data?['providers'];
        if (raw is List) {
          for (final p in raw) {
            if (p is Map) {
              final name = '${p['name'] ?? ''}'.trim();
              if (name.isEmpty) continue;
              providers.add(
                GatewayAuthProvider(
                  name: name,
                  displayName:
                      '${p['display_name'] ?? p['displayName'] ?? name}',
                  supportsPassword:
                      p['supports_password'] == true ||
                      p['supportsPassword'] == true,
                ),
              );
            }
          }
        }
      } catch (_) {
        // Optional metadata — auth mode already known.
      }
    }

    return GatewayAuthProbe(
      baseUrl: base,
      reachable: true,
      authMode: authRequired ? GatewayAuthMode.session : GatewayAuthMode.open,
      providers: providers,
      version: status?['version']?.toString(),
    );
  }

  /// POST /auth/password-login — Desktop login page body shape.
  Future<void> passwordLogin({
    required String provider,
    required String username,
    required String password,
  }) async {
    final urlError = validateBaseUrl(baseUrl);
    if (urlError != null) throw GatewayAuthException(urlError);
    final res = await dio.post<Map<String, dynamic>>(
      '/auth/password-login',
      data: {
        'provider': provider,
        'username': username,
        'password': password,
        'next': '',
      },
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    final code = res.statusCode ?? 0;
    if (code == 401) {
      throw GatewayAuthException('Invalid username or password.');
    }
    if (code == 429) {
      throw GatewayAuthException('Too many attempts. Wait and try again.');
    }
    if (code == 404) {
      throw GatewayAuthException('Unknown auth provider on this gateway.');
    }
    if (code < 200 || code >= 300) {
      final detail = res.data is Map ? res.data!['detail'] : null;
      throw GatewayAuthException(
        detail != null ? '$detail' : 'Sign-in failed (HTTP $code).',
      );
    }
    final ok = res.data is Map && res.data!['ok'] == true;
    if (!ok && code != 200) {
      throw GatewayAuthException('Sign-in failed.');
    }
    // Cookies are now in the jar via CookieManager.
  }

  /// POST /api/auth/ws-ticket — requires live session cookies.
  ///
  /// 401/403 → [GatewayAuthException.needsReauth]. Callers must prompt
  /// interactive login (no silent password re-login — kicks are intentional).
  Future<String> mintWsTicket({
    @Deprecated('Silent re-login removed; do not pass relogin')
    Future<void> Function()? relogin,
  }) async {
    final res = await dio.post<Map<String, dynamic>>(
      '/api/auth/ws-ticket',
      options: Options(
        contentType: Headers.jsonContentType,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GatewayAuthException(
        'Session expired. Sign in again.',
        needsReauth: true,
      );
    }
    if (res.statusCode != 200) {
      throw GatewayAuthException(
        'Could not mint WebSocket ticket (HTTP ${res.statusCode}).',
      );
    }
    final ticket = res.data?['ticket'];
    if (ticket is! String || ticket.isEmpty) {
      throw GatewayAuthException('Gateway did not return a WS ticket.');
    }
    return ticket;
  }

  /// Whether the jar currently has a session access cookie for [baseUrl].
  Future<bool> hasSessionCookie() async {
    final uri = Uri.parse(_normalize(baseUrl));
    final cookies = await _jar.loadForRequest(uri);
    return cookies.any(
      (c) =>
          c.name.contains('hermes_session_at') ||
          c.name.contains('hermes_session_rt'),
    );
  }
}

enum GatewayAuthMode {
  /// auth_required: true — cookie session (password or OAuth).
  session,

  /// auth_required: false — open / loopback (no password gate).
  open,

  unknown,
}

class GatewayAuthProvider {
  const GatewayAuthProvider({
    required this.name,
    required this.displayName,
    required this.supportsPassword,
  });

  final String name;
  final String displayName;
  final bool supportsPassword;
}

class GatewayAuthProbe {
  const GatewayAuthProbe({
    required this.baseUrl,
    required this.reachable,
    required this.authMode,
    this.providers = const [],
    this.version,
    this.error,
  });

  final String baseUrl;
  final bool reachable;
  final GatewayAuthMode authMode;
  final List<GatewayAuthProvider> providers;
  final String? version;
  final String? error;

  bool get isPasswordGateway =>
      authMode == GatewayAuthMode.session &&
      providers.isNotEmpty &&
      providers.every((p) => p.supportsPassword);

  List<GatewayAuthProvider> get passwordProviders =>
      providers.where((p) => p.supportsPassword).toList();
}

class GatewayAuthException implements Exception {
  GatewayAuthException(this.message, {this.needsReauth = false});
  final String message;
  final bool needsReauth;
  @override
  String toString() => message;
}
