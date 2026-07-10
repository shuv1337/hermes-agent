import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain/EncryptedSharedPreferences-backed cookie persistence.
///
/// [legacyStorage] is read once so existing installs migrate from the old
/// plaintext Application Support cookie files without signing users out.
class SecureCookieStorage implements Storage {
  SecureCookieStorage({
    required this.namespace,
    required this.secureStorage,
    this.legacyStorage,
  });

  final String namespace;
  final FlutterSecureStorage secureStorage;
  final Storage? legacyStorage;

  String _variant = '';

  String _storageKey(String key) => 'hermes_cookie:$namespace:$_variant:$key';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    _variant = 'ie${ignoreExpires ? 1 : 0}_ps${persistSession ? 1 : 0}';
    await legacyStorage?.init(persistSession, ignoreExpires);
  }

  @override
  Future<String?> read(String key) async {
    final secureKey = _storageKey(key);
    final secure = await secureStorage.read(key: secureKey);
    if (secure != null) return secure;

    final legacy = await legacyStorage?.read(key);
    if (legacy == null) return null;

    // One-way migration: secure write must succeed before plaintext removal.
    await secureStorage.write(key: secureKey, value: legacy);
    await legacyStorage?.delete(key);
    return legacy;
  }

  @override
  Future<void> write(String key, String value) {
    return secureStorage.write(key: _storageKey(key), value: value);
  }

  @override
  Future<void> delete(String key) async {
    await secureStorage.delete(key: _storageKey(key));
    await legacyStorage?.delete(key);
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await secureStorage.delete(key: _storageKey(key));
    }
    await legacyStorage?.deleteAll(keys);
  }
}
