// Wave-2 coverage: boot rehydration for a saved demo profile
// (`GatewayBookNotifier` in `lib/core/providers.dart`).
//
// The demo gateway binds a fresh ephemeral port every process launch, so a
// previously-saved demo profile's `baseUrl` is dead by the time the app
// reopens. `gatewayBookProvider` must boot the sandbox and rewrite the
// stored URL as part of resolving, before any client is built off it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/demo/demo_mode.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/providers.dart';

void main() {
  tearDown(() async {
    await DemoGatewayHolder.instance.shutdown();
  });

  test(
    'gatewayBookProvider boots the sandbox and rewrites a stale demo baseUrl',
    () async {
      final store = ConnectionStore.memory();
      const stale = ConnectionProfile(
        id: demoProfileId,
        baseUrl: 'http://127.0.0.1:1', // dead port from a "previous launch"
        authMode: 'session',
        username: demoUsername,
        label: 'Hermes Go sample',
      );
      await store.saveAsPrimary(stale);

      final container = ProviderContainer(
        overrides: [connectionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final book = await container.read(gatewayBookProvider.future);

      expect(DemoGatewayHolder.instance.isRunning, isTrue);
      final freshUri = DemoGatewayHolder.instance.baseUri;
      expect(freshUri, isNotNull);
      expect(book.resolved?.id, demoProfileId);
      expect(book.resolved?.baseUrl, freshUri.toString());
      expect(book.resolved?.baseUrl, isNot(stale.baseUrl));
      // Other fields survive the rewrite untouched.
      expect(book.resolved?.label, 'Hermes Go sample');
      expect(book.resolved?.username, demoUsername);

      // Rewritten in the store too, not just the in-memory provider state —
      // the next cold boot must see the fresh URL.
      final reread = await store.readBook();
      expect(reread.resolved?.baseUrl, freshUri.toString());
    },
  );

  test('rehydrateDemoIfNeeded re-boots after the server dies '
      '(simulated background reclaim)', () async {
    final store = ConnectionStore.memory();
    const stale = ConnectionProfile(
      id: demoProfileId,
      baseUrl: 'http://127.0.0.1:1',
    );
    await store.saveAsPrimary(stale);

    final container = ProviderContainer(
      overrides: [connectionStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final firstBook = await container.read(gatewayBookProvider.future);
    final firstUri = DemoGatewayHolder.instance.baseUri;
    expect(firstBook.resolved?.baseUrl, firstUri.toString());

    // iOS may reclaim the loopback socket while the app is backgrounded.
    await DemoGatewayHolder.instance.shutdown();
    expect(DemoGatewayHolder.instance.isRunning, isFalse);

    await container.read(gatewayBookProvider.notifier).rehydrateDemoIfNeeded();

    expect(DemoGatewayHolder.instance.isRunning, isTrue);
    final secondUri = DemoGatewayHolder.instance.baseUri;
    final updated = container.read(gatewayBookProvider).value;
    expect(updated?.resolved?.baseUrl, secondUri.toString());
  });

  test('a non-demo profile is left completely untouched', () async {
    final store = ConnectionStore.memory();
    const other = ConnectionProfile(
      id: 'not-demo',
      baseUrl: 'https://example.com',
    );
    await store.saveAsPrimary(other);

    final container = ProviderContainer(
      overrides: [connectionStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final book = await container.read(gatewayBookProvider.future);
    expect(book.resolved?.baseUrl, 'https://example.com');
    expect(DemoGatewayHolder.instance.isRunning, isFalse);
  });
}
