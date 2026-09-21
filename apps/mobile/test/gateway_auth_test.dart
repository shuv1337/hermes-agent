import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/network/gateway_auth.dart';
import 'package:hermes_mobile/core/network/gateway_ws_client.dart';

void main() {
  group('gateway URL validation', () {
    test('allows HTTPS and loopback development HTTP', () {
      expect(
        GatewayAuthClient.validateBaseUrl('https://gw.example:9119'),
        isNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://127.0.0.1:9119'),
        isNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://localhost:9119/'),
        isNull,
      );
    });

    test('rejects insecure remote credentials, paths, and incomplete URLs', () {
      expect(
        GatewayAuthClient.validateBaseUrl('https://user:pass@gw.example'),
        isNotNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('https://gw.example/prefix'),
        isNotNull,
      );
      expect(GatewayAuthClient.validateBaseUrl('gw.example'), isNotNull);
    });

    test('allows HTTP for private/trusted network space', () {
      // RFC1918 — 192.168.0.0/16 (was rejected pre-policy-change).
      expect(
        GatewayAuthClient.validateBaseUrl('http://192.168.1.20:9119'),
        isNull,
      );
      // RFC1918 — 10.0.0.0/8, including the Android emulator host alias.
      expect(GatewayAuthClient.validateBaseUrl('http://10.0.2.2:9119'), isNull);
      expect(
        GatewayAuthClient.validateBaseUrl('http://10.255.255.255:9119'),
        isNull,
      );
      // RFC1918 — 172.16.0.0/12 boundary.
      expect(
        GatewayAuthClient.validateBaseUrl('http://172.16.0.1:9119'),
        isNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://172.31.255.255:9119'),
        isNull,
      );
      // CGNAT — 100.64.0.0/10 (Tailscale tailnet IPs).
      expect(
        GatewayAuthClient.validateBaseUrl('http://100.64.0.1:9119'),
        isNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://100.127.255.255:9119'),
        isNull,
      );
      // link-local
      expect(
        GatewayAuthClient.validateBaseUrl('http://169.254.1.1:9119'),
        isNull,
      );
      // mDNS
      expect(
        GatewayAuthClient.validateBaseUrl('http://myhost.local:9119'),
        isNull,
      );
      // Tailscale MagicDNS
      expect(
        GatewayAuthClient.validateBaseUrl('http://myhost.tailnet.ts.net:9119'),
        isNull,
      );
    });

    test('blocks HTTP just outside the private/trusted ranges', () {
      // 172.16.0.0/12 boundary — 172.15.x and 172.32.x are public.
      expect(
        GatewayAuthClient.validateBaseUrl('http://172.15.255.255:9119'),
        isNotNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://172.32.0.1:9119'),
        isNotNull,
      );
      // 100.64.0.0/10 boundary — 100.63.x and 100.128.x are public.
      expect(
        GatewayAuthClient.validateBaseUrl('http://100.63.255.255:9119'),
        isNotNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://100.128.0.1:9119'),
        isNotNull,
      );
    });

    test('blocks HTTP to the public internet', () {
      expect(
        GatewayAuthClient.validateBaseUrl('http://example.com:9119'),
        isNotNull,
      );
      expect(
        GatewayAuthClient.validateBaseUrl('http://8.8.8.8:9119'),
        isNotNull,
      );
    });

    test(
      'hardening the host classifier rejected nothing it used to accept',
      () {
        // Every URL the validator accepted before the private/loopback
        // classifier learned about non-canonical address forms. Tightening the
        // *image* gate must never cost a user their gateway.
        for (final url in [
          'https://gw.example:9119',
          'https://gw.example',
          'https://GW.Example:9119/',
          'http://127.0.0.1:9119',
          'http://127.0.0.1',
          'http://localhost:9119/',
          'http://localhost',
          'http://192.168.1.20:9119',
          'http://10.0.2.2:9119',
          'http://10.255.255.255:9119',
          'http://172.16.0.1:9119',
          'http://172.31.255.255:9119',
          'http://100.64.0.1:9119',
          'http://100.127.255.255:9119',
          'http://169.254.1.1:9119',
          'http://myhost.local:9119',
          'http://myhost.tailnet.ts.net:9119',
          'http://[fd00::1]:9119',
          'http://[fdaa:0:2c:a7b::1]:9119',
        ]) {
          expect(GatewayAuthClient.validateBaseUrl(url), isNull, reason: url);
        }
      },
    );

    test('still refuses plain HTTP to anything public', () {
      for (final url in [
        'http://example.com:9119',
        'http://gw.example',
        'http://8.8.8.8:9119',
        'http://1.1.1.1',
        'http://172.15.255.255:9119',
        'http://172.32.0.1:9119',
        'http://100.63.255.255:9119',
        'http://100.128.0.1:9119',
        'http://[2001:db8::1]:9119',
      ]) {
        expect(GatewayAuthClient.validateBaseUrl(url), isNotNull, reason: url);
      }
    });

    test('the new address forms are treated as the private hosts they are', () {
      // These all resolve to loopback/LAN, so plain HTTP to them is as
      // acceptable as `http://127.0.0.1` — a widening, never a rejection.
      for (final url in [
        'http://0.0.0.0:9119',
        'http://127.1:9119',
        'http://2130706433:9119',
        'http://0x7f000001:9119',
        'http://[::1]:9119',
        'http://[0:0:0:0:0:0:0:1]:9119',
        'http://[::ffff:192.168.1.1]:9119',
        'http://[fe80::1]:9119',
      ]) {
        expect(GatewayAuthClient.validateBaseUrl(url), isNull, reason: url);
      }
    });
  });

  group('isPrivateOrLoopbackHost', () {
    test('classifies every spelling of a private or loopback address', () {
      for (final host in [
        // Plain forms that already worked.
        'localhost',
        '127.0.0.1',
        '10.0.0.5',
        '192.168.1.1',
        '172.16.4.4',
        '169.254.169.254',
        '100.100.1.1',
        'gateway.local',
        'box.ts.net',
        'fd00::1',
        // fe80::/10 link-local — only fc/fd used to be checked.
        'fe80::1',
        'fe80::200:5aee:feaa:20a2',
        'febf::1',
        '[fe80::1%25en0]', // zone id, as `Uri` percent-encodes it
        // The unspecified address.
        '0.0.0.0',
        '::',
        // IPv4-mapped IPv6.
        '::ffff:192.168.1.1',
        '::ffff:127.0.0.1',
        '::ffff:10.0.0.1',
        // Non-canonical IPv6 loopback — `Uri` does not canonicalise.
        '0:0:0:0:0:0:0:1',
        '0000:0000:0000:0000:0000:0000:0000:0001',
        '::1',
        // Integer / hex / octal / short IPv4, all of which `connect()`
        // resolves to 127.0.0.1.
        '2130706433',
        '0x7f000001',
        '127.1',
        '127.0.1',
        '0177.0.0.1',
        // Multicast and reserved space — not something to offer a tap for.
        '224.0.0.1',
        '255.255.255.255',
        'ff02::1',
        // Case and trailing-dot spellings of the same names.
        'GATEWAY.LOCAL',
        'gateway.local.',
      ]) {
        expect(
          GatewayAuthClient.isPrivateOrLoopbackHost(host),
          isTrue,
          reason: host,
        );
      }
    });

    test('fails closed for anything not recognisably public', () {
      for (final host in [
        '', // nothing to vet
        'intranet', // single label → DHCP search domain → the LAN
        'gateway',
        'localhost6',
        'fe80:::1', // malformed IPv6
        ':::',
        'host_name..double', // not a legal hostname
        '-leading-hyphen.example',
        'trailing.example-', // label cannot end in a hyphen
        'host.123', // numeric TLD is not a real TLD
        'host.c', // single-letter TLD does not exist
      ]) {
        expect(
          GatewayAuthClient.isPrivateOrLoopbackHost(host),
          isTrue,
          reason: host,
        );
      }
    });

    test('genuine public hosts stay public', () {
      for (final host in [
        'example.com',
        'attacker.example',
        'images.cdn.example.co.uk',
        'xn--80ak6aa92e.com', // IDN A-label
        'sub.xn--p1ai', // IDN TLD
        '8.8.8.8',
        '1.1.1.1',
        '172.15.255.255',
        '172.32.0.1',
        '100.63.255.255',
        '2001:db8::1',
        '2606:4700:4700::1111',
      ]) {
        expect(
          GatewayAuthClient.isPrivateOrLoopbackHost(host),
          isFalse,
          reason: host,
        );
      }
    });
  });

  test('password gateway shape: all providers support password', () {
    const probe = GatewayAuthProbe(
      baseUrl: 'https://gw.example',
      reachable: true,
      authMode: GatewayAuthMode.session,
      providers: [
        GatewayAuthProvider(
          name: 'basic',
          displayName: 'Username & Password',
          supportsPassword: true,
        ),
      ],
    );
    expect(probe.isPasswordGateway, isTrue);
    expect(probe.passwordProviders.single.name, 'basic');
  });

  test('mixed OAuth+password is not pure password gateway', () {
    const probe = GatewayAuthProbe(
      baseUrl: 'https://gw.example',
      reachable: true,
      authMode: GatewayAuthMode.session,
      providers: [
        GatewayAuthProvider(
          name: 'basic',
          displayName: 'Password',
          supportsPassword: true,
        ),
        GatewayAuthProvider(
          name: 'nous',
          displayName: 'Nous',
          supportsPassword: false,
        ),
      ],
    );
    // Mirrors Desktop deriveProviderShape: every provider must support password.
    expect(probe.isPasswordGateway, isFalse);
  });

  test('WS URL uses ticket for session auth, token for legacy', () {
    final withTicket = GatewayWsClient.buildWsUrl(
      'https://gw.example:9119',
      ticket: 'abc',
    );
    expect(withTicket, contains('ticket=abc'));
    expect(withTicket, startsWith('wss://'));

    final withToken = GatewayWsClient.buildWsUrl(
      'http://127.0.0.1:9119',
      token: 'static',
    );
    expect(withToken, contains('token=static'));
    expect(withToken, startsWith('ws://'));
  });
}
