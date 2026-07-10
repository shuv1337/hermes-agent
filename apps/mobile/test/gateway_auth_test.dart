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

    test(
      'rejects insecure remote, credentials, paths, and incomplete URLs',
      () {
        expect(
          GatewayAuthClient.validateBaseUrl('http://192.168.1.20:9119'),
          isNotNull,
        );
        expect(
          GatewayAuthClient.validateBaseUrl('https://user:pass@gw.example'),
          isNotNull,
        );
        expect(
          GatewayAuthClient.validateBaseUrl('https://gw.example/prefix'),
          isNotNull,
        );
        expect(GatewayAuthClient.validateBaseUrl('gw.example'), isNotNull);
      },
    );
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
