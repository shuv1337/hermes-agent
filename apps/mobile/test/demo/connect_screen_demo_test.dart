// Wave-2 coverage: the connect screen's reserved-host interception
// (`lib/features/connect/connect_screen.dart` `_probeUrl`). Typing the
// demo host must boot the real in-process `DemoGatewayServer` and drive the
// screen's *real* probe flow against its loopback URL — never against
// `demo.hermes.go` itself (which is not expected to resolve).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/demo/demo_mode.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/connect/connect_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Same trick as `test/demo/demo_gateway_server_test.dart`: opt this test's
/// network calls out of `flutter_test`'s always-400 fake `HttpClient` so the
/// probe genuinely reaches the loopback `DemoGatewayServer`.
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await DemoGatewayHolder.instance.shutdown();
  });

  testWidgets(
    'typing demo.hermes.go boots the sandbox and reaches the password form',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionStoreProvider.overrideWithValue(ConnectionStore.memory()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: supportedAppLocales,
            home: ConnectScreen(),
          ),
        ),
      );
      await tester.pump();

      // Bare host, no scheme — exactly what the App Review notes tell a
      // reviewer to type, and what the validator must accept for this one
      // reserved hostname.
      await tester.enterText(find.byType(TextFormField).first, demoGatewayHost);
      await tester.pump();

      await tester.runAsync(() async {
        await HttpOverrides.runWithHttpOverrides(() async {
          await tester.tap(find.text('Continue'));
          await tester.pump();
          // The probe is real async I/O (ensureRunning binds a real socket,
          // then a real Dio GET) — outside FakeAsync's synchronous flush, so
          // poll with real delays until the password form shows up.
          for (
            var i = 0;
            i < 100 && find.text('Username').evaluate().isEmpty;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        }, _RealHttpOverrides());
      });

      expect(DemoGatewayHolder.instance.isRunning, isTrue);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      // The interception must never leave the demo hostname as the dialed
      // base URL — everything downstream targets the loopback server.
      expect(
        DemoGatewayHolder.instance.baseUri?.host,
        anyOf('127.0.0.1', 'localhost'),
      );
    },
  );
}
