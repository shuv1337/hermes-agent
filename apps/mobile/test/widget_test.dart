import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/providers.dart';

void main() {
  testWidgets('Connect screen boots without a saved profile', (tester) async {
    await tester.pumpWidget(
      HermesMobileApp(
        providerOverrides: [
          connectionStoreProvider.overrideWithValue(ConnectionStore.memory()),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Gateway base URL'), findsOneWidget);
    expect(find.textContaining('No API key'), findsOneWidget);
    expect(
      find.text(
        'Unofficial · Community-built · Not affiliated with Nous Research',
      ),
      findsOneWidget,
    );
    expect(find.text('Privacy & data'), findsOneWidget);

    await tester.tap(find.text('Privacy & data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sends conversations and attachments'),
      findsOneWidget,
    );
    expect(find.textContaining('Publisher action required'), findsOneWidget);
  });

  testWidgets('Connect screen remains scrollable at very large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(3.2),
        ),
        child: HermesMobileApp(
          providerOverrides: [
            connectionStoreProvider.overrideWithValue(ConnectionStore.memory()),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Unofficial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
