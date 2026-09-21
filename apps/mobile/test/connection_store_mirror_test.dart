// Regression coverage for the RST "Application Support gateway-book mirror"
// finding: ConnectionStore._writeMirror() must never write
// ConnectionProfile.apiKey (or any other secret) to the plaintext
// Application Support mirror file, and readBook() must scrub any secret an
// old (pre-fix) build already left sitting in that file, on the very next
// launch -- not just stop writing new ones.
//
// Mocking pattern mirrors test/demo/demo_gateway_server_test.dart: fake the
// path_provider and flutter_secure_storage platform channels so
// ConnectionStore()'s real (non-.memory()) constructor exercises the actual
// mirror-file code path.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late Map<String, String> secureValues;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('hermes_mirror_test_');
    secureValues = <String, String>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => supportDir.path,
        );

    // Same fake as demo_gateway_server_test.dart: an in-memory map standing
    // in for Keychain / EncryptedSharedPreferences.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments;
            final key = args is Map ? args['key'] as String? : null;
            switch (call.method) {
              case 'read':
                return key == null ? null : secureValues[key];
              case 'write':
                if (key != null) {
                  secureValues[key] = (args as Map)['value'] as String;
                }
                return null;
              case 'delete':
                if (key != null) secureValues.remove(key);
                return null;
              case 'deleteAll':
                secureValues.clear();
                return null;
              case 'containsKey':
                return key != null && secureValues.containsKey(key);
              case 'readAll':
                return secureValues;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });

  File mirrorFile() =>
      File('${supportDir.path}/${ConnectionStore.mirrorFileName}');

  // Shape a pre-fix build would have written: GatewayBook.toJson() with
  // ConnectionProfile.apiKey included in plaintext.
  Map<String, dynamic> legacyPlaintextBookJson(String apiKey) => {
    'version': 2,
    'gateways': [
      {
        'id': 'gw1',
        'baseUrl': 'https://gateway.example:8642',
        'apiKey': apiKey,
        'authMode': 'token',
        'label': 'Home',
      },
    ],
    'defaultGatewayId': 'gw1',
    'activeGatewayId': 'gw1',
  };

  test('readBook scrubs a pre-existing plaintext apiKey from the mirror file '
      'while secure storage stays intact', () async {
    const leaked = 'super-secret-legacy-token';

    // Healthy/common case: secure storage already holds the full profile
    // (including the secret) -- but an old build also left the same
    // secret sitting in the plaintext Application Support mirror.
    secureValues['hermes_mobile_gateway_book_v2'] = jsonEncode(
      legacyPlaintextBookJson(leaked),
    );
    await mirrorFile().parent.create(recursive: true);
    await mirrorFile().writeAsString(
      jsonEncode(legacyPlaintextBookJson(leaked)),
    );

    final book = await ConnectionStore().readBook();

    // Secure storage remains the source of truth for the secret.
    expect(book.gateways.single.apiKey, leaked);

    // readBook() must have rewritten the on-disk mirror without it.
    final onDisk = await mirrorFile().readAsString();
    expect(onDisk.contains(leaked), isFalse);
    expect(onDisk.contains('apiKey'), isFalse);

    final reparsed = jsonDecode(onDisk) as Map<String, dynamic>;
    final gw = (reparsed['gateways'] as List).single as Map;
    expect(gw['baseUrl'], 'https://gateway.example:8642');
    expect(gw.containsKey('apiKey'), isFalse);
  });

  test('mirror-only recovery restores the secret to secure storage but still '
      'scrubs the mirror file itself', () async {
    const leaked = 'recovered-legacy-token';

    // Secure storage is empty (keychain hiccup / fresh secure-storage
    // backing store), but the old plaintext mirror still has the full
    // pre-fix blob -- exercises ConnectionStore's post-upgrade recovery
    // branch (_readBookImpl step 2: re-seed keychain from the mirror).
    await mirrorFile().parent.create(recursive: true);
    await mirrorFile().writeAsString(
      jsonEncode(legacyPlaintextBookJson(leaked)),
    );

    final store = ConnectionStore();
    final book = await store.readBook();

    // Recovery re-seeds secure storage from the mirror, so the secret
    // itself is not lost...
    expect(book.gateways.single.apiKey, leaked);
    expect(secureValues['hermes_mobile_gateway_book_v2'], isNotNull);

    // ...but the mirror file on disk must come out scrubbed regardless.
    final onDisk = await mirrorFile().readAsString();
    expect(onDisk.contains(leaked), isFalse);
    expect(onDisk.contains('apiKey'), isFalse);
  });

  test('a freshly written book never puts apiKey in the mirror file', () async {
    final store = ConnectionStore();
    await store.saveAsPrimary(
      ConnectionProfile(
        id: store.newGatewayId(),
        baseUrl: 'https://fresh.example:8642',
        apiKey: 'brand-new-secret',
        label: 'Fresh',
      ),
    );

    final onDisk = await mirrorFile().readAsString();
    expect(onDisk.contains('brand-new-secret'), isFalse);
    expect(onDisk.contains('apiKey'), isFalse);
  });
}
