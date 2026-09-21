import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';

void main() {
  group('GatewayBook', () {
    test('round-trips json with default and active', () {
      const book = GatewayBook(
        gateways: [
          ConnectionProfile(
            id: 'a',
            baseUrl: 'https://a.example:8642',
            apiKey: 'key-a',
            label: 'Home',
          ),
          ConnectionProfile(
            id: 'b',
            baseUrl: 'https://b.example:8642',
            apiKey: 'key-b',
            label: 'Spark',
            botModeAvailable: true,
          ),
        ],
        defaultGatewayId: 'a',
        activeGatewayId: 'b',
      );

      final restored = GatewayBook.fromJson(book.toJson());
      expect(restored.gateways.length, 2);
      expect(restored.defaultGatewayId, 'a');
      expect(restored.activeGatewayId, 'b');
      expect(restored.active?.label, 'Spark');
      expect(restored.defaultGateway?.label, 'Home');
      expect(restored.resolved?.id, 'b');
      expect(restored.active?.botModeAvailable, isTrue);
    });

    test('resolved falls back to default then sole gateway', () {
      const sole = GatewayBook(
        gateways: [
          ConnectionProfile(
            id: 'only',
            baseUrl: 'http://127.0.0.1:8642',
            apiKey: 'k',
          ),
        ],
      );
      expect(sole.resolved?.id, 'only');

      const withDefault = GatewayBook(
        gateways: [
          ConnectionProfile(id: 'd', baseUrl: 'http://d:8642', apiKey: 'k'),
          ConnectionProfile(id: 'x', baseUrl: 'http://x:8642', apiKey: 'k'),
        ],
        defaultGatewayId: 'd',
      );
      expect(withDefault.resolved?.id, 'd');
    });
  });

  group('ConnectionStore multi-gateway API', () {
    test('v1 saveAsPrimary then multi upsert/setActive/setDefault', () async {
      final store = ConnectionStore.memory();
      final primary = ConnectionProfile(
        id: store.newGatewayId(),
        baseUrl: 'http://home:8642',
        apiKey: 'home-key',
        label: 'Home',
      );
      var book = await store.saveAsPrimary(primary);
      expect(book.gateways.length, 1);
      expect(book.defaultGatewayId, primary.id);
      expect(book.activeGatewayId, primary.id);

      final other = ConnectionProfile(
        id: store.newGatewayId(),
        baseUrl: 'http://spark:8642',
        apiKey: 'spark-key',
        label: 'Spark',
      );
      book = await store.upsertGateway(other);
      expect(book.gateways.length, 2);

      book = await store.setActive(other.id);
      expect(book.activeGatewayId, other.id);
      expect(book.defaultGatewayId, primary.id);

      book = await store.setDefault(other.id);
      expect(book.defaultGatewayId, other.id);

      await store.writeSelectedModel(other.id, 'hermes-agent');
      expect(await store.readSelectedModel(other.id), 'hermes-agent');

      book = await store.removeGateway(other.id);
      expect(book.gateways.length, 1);
      expect(book.activeGatewayId, primary.id);
    });

    test('migrates legacy single-profile blob', () async {
      final store = ConnectionStore.memory({
        'hermes_mobile_connection':
            '{"baseUrl":"http://legacy:8642","apiKey":"leg-key","displayName":"m"}',
      });
      final book = await store.readBook();
      expect(book.gateways.length, 1);
      expect(book.gateways.first.baseUrl, 'http://legacy:8642');
      expect(book.defaultGatewayId, book.gateways.first.id);
      expect(book.activeGatewayId, book.gateways.first.id);
    });

    test('disconnect removes legacy stored passwords', () async {
      final memory = <String, String>{};
      final store = ConnectionStore.memory(memory);
      const profile = ConnectionProfile(
        id: 'gw',
        baseUrl: 'https://gw.example',
      );
      await store.saveAsPrimary(profile);
      memory['hermes_mobile_password:gw'] = 'do-not-keep';

      await store.disconnectAll();

      expect(memory.containsKey('hermes_mobile_password:gw'), isFalse);
    });

    test('rememberBotMode persists a positive per-gateway hint', () async {
      final store = ConnectionStore.memory();
      const profile = ConnectionProfile(
        id: 'gw',
        baseUrl: 'https://gw.example',
      );
      await store.saveAsPrimary(profile);

      await store.rememberBotMode(profile.id);

      final restored = await store.readBook();
      expect(restored.resolved?.botModeAvailable, isTrue);
      expect(restored.resolved?.toMirrorJson()['botModeAvailable'], isTrue);
    });
  });
}
