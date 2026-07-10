import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';

/// Persists gateway credentials on device across app **upgrades / deploys**.
///
/// ## Durability contract (do not break on deploy)
/// - **Never uninstall-then-install** the app when shipping a build. That wipes
///   the sandbox mirror. Use upgrade install only (`scripts/deploy_ios.sh`).
/// - Credentials live in the **iOS Keychain** (stable account + access group)
///   and are **mirrored** into Application Support so a keychain hiccup after
///   Xcode/flutter upgrade still restores the gateway book.
/// - Storage schema is multi-gateway ([GatewayBook] v2) even though v1 UI is
///   single-gateway.
///
/// Keys / account names are **stable forever** — renaming them orphans data.
class ConnectionStore {
  ConnectionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? durableSecureStorage(),
      _legacyStorage = storage == null ? _defaultPluginStorage() : null,
      _memory = null;

  ConnectionStore.memory([Map<String, String>? initial])
    : _storage = null,
      _legacyStorage = null,
      _memory = initial ?? <String, String>{};

  /// Canonical secure-storage config. Keep these constants stable across releases.
  static const keychainAccountName = 'ai.hermes.hermesMobile.gateways';
  static const keychainAccessGroup = '4WF3G6AN6G.ai.hermes.go';
  static const androidPrefsName = 'ai.hermes.hermesMobile.gateways';
  static const mirrorFileName = 'gateway_book_v2.json';

  static const _bookKey = 'hermes_mobile_gateway_book_v2';
  static const _legacyProfileKey = 'hermes_mobile_connection';
  static const _selectedModelPrefix = 'hermes_mobile_selected_model:';
  static const _selectedProviderPrefix = 'hermes_mobile_selected_provider:';
  static const _selectedEffortPrefix = 'hermes_mobile_selected_effort:';
  static const _selectedFastPrefix = 'hermes_mobile_selected_fast:';
  static const _modelOptionsPrefix = 'hermes_mobile_model_options:';
  static const _pinnedSessionsPrefix = 'hermes_mobile_pinned_sessions:';

  /// sessionId → last-read activity token (lastActive / startedAt when opened).
  static const _sessionReadPrefix = 'hermes_mobile_session_read:';

  /// Legacy password key. Kept only so explicit disconnect/reauth can erase
  /// passwords written by pre-release builds; new builds never store one.
  static const _passwordPrefix = 'hermes_mobile_password:';
  static const _legacySelectedModelKey = 'hermes_mobile_selected_model';
  static const _skinKey = 'hermes_mobile_skin';
  static const _themeModeKey = 'hermes_mobile_theme_mode';

  /// UI language override: empty / missing = follow system.
  static const _localeKey = 'hermes_mobile_locale';

  /// Desktop `$hapticsMuted` — gates haptics + completion sounds together.
  static const _hapticsMutedKey = 'hermes_mobile_haptics_muted';

  /// Production Keychain / EncryptedSharedPreferences backend.
  ///
  /// Intentionally **no** custom `groupId` — a mismatched keychain-access-groups
  /// entitlement crashes/fails reads on device. Default app keychain + stable
  /// [accountName] still survives upgrade installs; Application Support mirror
  /// is the second line of defense.
  static FlutterSecureStorage durableSecureStorage() {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: keychainAccountName,
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        sharedPreferencesName: androidPrefsName,
        preferencesKeyPrefix: 'hermes_',
        resetOnError: false,
      ),
    );
  }

  /// Pre-durability plugin defaults (migration source only).
  static FlutterSecureStorage _defaultPluginStorage() {
    return const FlutterSecureStorage();
  }

  final FlutterSecureStorage? _storage;
  final FlutterSecureStorage? _legacyStorage;
  final Map<String, String>? _memory;
  final _uuid = const Uuid();

  Future<String?> _read(String key) async {
    final memory = _memory;
    if (memory != null) return memory[key];
    return _storage!.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    final memory = _memory;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    await _storage!.write(key: key, value: value);
  }

  Future<void> _delete(String key) async {
    final memory = _memory;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    await _storage!.delete(key: key);
  }

  // ── Application Support mirror (survives upgrade installs) ─────────

  Future<File?> _mirrorFile() async {
    if (_memory != null) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$mirrorFileName');
    } catch (e) {
      debugPrint('ConnectionStore: mirror path unavailable: $e');
      return null;
    }
  }

  Future<void> _writeMirror(GatewayBook book) async {
    final file = await _mirrorFile();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(book.toJson()), flush: true);
    } catch (e) {
      debugPrint('ConnectionStore: mirror write failed: $e');
    }
  }

  Future<GatewayBook?> _readMirror() async {
    final file = await _mirrorFile();
    if (file == null || !await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final book = GatewayBook.fromJson(
        parsed.map((k, v) => MapEntry('$k', v)),
      );
      return book.isEmpty ? null : book;
    } catch (e) {
      debugPrint('ConnectionStore: mirror read failed: $e');
      return null;
    }
  }

  Future<void> _clearMirror() async {
    final file = await _mirrorFile();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── Gateway book ───────────────────────────────────────────────────

  Future<GatewayBook> readBook() async {
    // 1) Durable keychain / prefs
    final fromSecure = await _parseBook(await _read(_bookKey));
    if (fromSecure != null && fromSecure.isNotEmpty) {
      // Keep mirror warm after successful secure read.
      await _writeMirror(fromSecure);
      return fromSecure;
    }

    // 2) Application Support mirror (post-upgrade recovery)
    final fromMirror = await _readMirror();
    if (fromMirror != null && fromMirror.isNotEmpty) {
      await writeBook(fromMirror); // re-seed keychain
      return fromMirror;
    }

    // 3) Legacy single-profile key on durable storage
    final legacy = await _readLegacyProfileFrom(_storage);
    if (legacy != null) {
      final book = GatewayBook(
        gateways: [legacy],
        defaultGatewayId: legacy.id,
        activeGatewayId: legacy.id,
      );
      await writeBook(book);
      await _delete(_legacyProfileKey);
      return book;
    }

    // 4) Pre-durability default plugin storage → migrate forward once
    final fromPluginDefault = await _migrateFromDefaultPluginStorage();
    if (fromPluginDefault != null) return fromPluginDefault;

    return GatewayBook.empty;
  }

  Future<GatewayBook?> _migrateFromDefaultPluginStorage() async {
    final legacyPlugin = _legacyStorage;
    if (legacyPlugin == null) return null;
    try {
      final rawBook = await legacyPlugin.read(key: _bookKey);
      final book = await _parseBook(rawBook);
      if (book != null && book.isNotEmpty) {
        await writeBook(book);
        await legacyPlugin.delete(key: _bookKey);
        return book;
      }
      final rawLegacy = await legacyPlugin.read(key: _legacyProfileKey);
      if (rawLegacy != null && rawLegacy.isNotEmpty) {
        final profile = _profileFromLegacyJson(rawLegacy);
        if (profile != null) {
          final migrated = GatewayBook(
            gateways: [profile],
            defaultGatewayId: profile.id,
            activeGatewayId: profile.id,
          );
          await writeBook(migrated);
          await legacyPlugin.delete(key: _legacyProfileKey);
          return migrated;
        }
      }
    } catch (e) {
      debugPrint('ConnectionStore: legacy plugin migrate failed: $e');
    }
    return null;
  }

  Future<GatewayBook?> _parseBook(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final book = GatewayBook.fromJson(
        parsed.map((k, v) => MapEntry('$k', v)),
      );
      return book.isEmpty ? null : book;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeBook(GatewayBook book) async {
    final encoded = jsonEncode(book.toJson());
    await _write(_bookKey, encoded);
    await _writeMirror(book);
  }

  Future<void> clearBook() async {
    await _delete(_bookKey);
    await _delete(_legacyProfileKey);
    await _clearMirror();
  }

  Future<ConnectionProfile?> _readLegacyProfileFrom(
    FlutterSecureStorage? storage,
  ) async {
    if (storage == null && _memory == null) return null;
    final memory = _memory;
    final raw = memory != null
        ? memory[_legacyProfileKey]
        : await storage!.read(key: _legacyProfileKey);
    return _profileFromLegacyJson(raw);
  }

  ConnectionProfile? _profileFromLegacyJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final map = parsed.map((k, v) => MapEntry('$k', v));
      final baseUrl = '${map['baseUrl'] ?? ''}'.trim();
      final apiKey = '${map['apiKey'] ?? ''}';
      if (baseUrl.isEmpty) return null;
      final existingId = '${map['id'] ?? ''}'.trim();
      return ConnectionProfile(
        id: existingId.isNotEmpty ? existingId : _uuid.v4(),
        baseUrl: baseUrl,
        apiKey: apiKey,
        displayName: map['displayName'] as String?,
        label: map['label'] as String?,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      return null;
    }
  }

  /// v1 convenience: active (resolved) profile, or null if none saved.
  Future<ConnectionProfile?> readActiveProfile() async {
    final book = await readBook();
    return book.resolved;
  }

  /// v1 connect path: upsert as the sole / active / default gateway.
  Future<GatewayBook> saveAsPrimary(ConnectionProfile profile) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final withMeta = profile.copyWith(
      createdAt: profile.createdAt ?? now,
      lastUsedAt: now,
    );

    final existing = await readBook();
    if (existing.gateways.length > 1) {
      final others = existing.gateways
          .where((g) => g.id != withMeta.id)
          .toList();
      final merged = GatewayBook(
        gateways: [...others, withMeta],
        defaultGatewayId: existing.defaultGatewayId ?? withMeta.id,
        activeGatewayId: withMeta.id,
      );
      await writeBook(merged);
      return merged;
    }

    final book = GatewayBook(
      gateways: [withMeta],
      defaultGatewayId: withMeta.id,
      activeGatewayId: withMeta.id,
    );
    await writeBook(book);
    return book;
  }

  Future<GatewayBook> upsertGateway(ConnectionProfile profile) async {
    final book = await readBook();
    final list = [...book.gateways];
    final idx = list.indexWhere((g) => g.id == profile.id);
    if (idx >= 0) {
      list[idx] = profile;
    } else {
      list.add(profile);
    }
    final next = book.copyWith(
      gateways: list,
      defaultGatewayId: book.defaultGatewayId ?? profile.id,
      activeGatewayId: book.activeGatewayId ?? profile.id,
    );
    await writeBook(next);
    return next;
  }

  Future<GatewayBook> setActive(String gatewayId) async {
    final book = await readBook();
    if (!book.gateways.any((g) => g.id == gatewayId)) {
      return book;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final list = book.gateways
        .map((g) => g.id == gatewayId ? g.copyWith(lastUsedAt: now) : g)
        .toList();
    final next = book.copyWith(gateways: list, activeGatewayId: gatewayId);
    await writeBook(next);
    return next;
  }

  Future<GatewayBook> setDefault(String gatewayId) async {
    final book = await readBook();
    if (!book.gateways.any((g) => g.id == gatewayId)) {
      return book;
    }
    final next = book.copyWith(defaultGatewayId: gatewayId);
    await writeBook(next);
    return next;
  }

  Future<GatewayBook> removeGateway(String gatewayId) async {
    final book = await readBook();
    final list = book.gateways.where((g) => g.id != gatewayId).toList();
    String? def = book.defaultGatewayId;
    String? act = book.activeGatewayId;
    if (def == gatewayId) def = list.isEmpty ? null : list.first.id;
    if (act == gatewayId) act = def ?? (list.isEmpty ? null : list.first.id);
    final next = GatewayBook(
      gateways: list,
      defaultGatewayId: def,
      activeGatewayId: act,
    );
    await writeBook(next);
    await clearSelectedModel(gatewayId);
    await clearPassword(gatewayId);
    if (list.isEmpty) {
      await clearBook();
      return GatewayBook.empty;
    }
    return next;
  }

  /// Explicit user disconnect only — never call this from deploy scripts.
  Future<void> disconnectAll() async {
    final book = await readBook();
    for (final g in book.gateways) {
      await clearSelectedModel(g.id);
      await clearPassword(g.id);
    }
    await clearSelectedModel(null);
    await clearBook();
  }

  // ── Per-gateway selected model ─────────────────────────────────────

  String _modelKey(String? gatewayId) {
    if (gatewayId == null || gatewayId.isEmpty) {
      return _legacySelectedModelKey;
    }
    return '$_selectedModelPrefix$gatewayId';
  }

  Future<String?> readSelectedModel(String? gatewayId) async {
    final scoped = await _read(_modelKey(gatewayId));
    if (scoped != null && scoped.isNotEmpty) return scoped;
    if (gatewayId != null) {
      return _read(_legacySelectedModelKey);
    }
    return null;
  }

  Future<void> writeSelectedModel(String gatewayId, String modelId) =>
      _write(_modelKey(gatewayId), modelId);

  String _providerKey(String? gatewayId) {
    if (gatewayId == null || gatewayId.isEmpty) {
      return '${_selectedProviderPrefix}legacy';
    }
    return '$_selectedProviderPrefix$gatewayId';
  }

  Future<String?> readSelectedProvider(String? gatewayId) async {
    final v = await _read(_providerKey(gatewayId));
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> writeSelectedProvider(String gatewayId, String provider) =>
      _write(_providerKey(gatewayId), provider);

  String _effortKey(String? gatewayId) {
    if (gatewayId == null || gatewayId.isEmpty) {
      return '${_selectedEffortPrefix}legacy';
    }
    return '$_selectedEffortPrefix$gatewayId';
  }

  /// Sticky reasoning effort (`none|minimal|low|medium|high|xhigh`).
  Future<String?> readSelectedEffort(String? gatewayId) async {
    final v = await _read(_effortKey(gatewayId));
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> writeSelectedEffort(String gatewayId, String effort) =>
      _write(_effortKey(gatewayId), effort);

  String _fastKey(String? gatewayId) {
    if (gatewayId == null || gatewayId.isEmpty) {
      return '${_selectedFastPrefix}legacy';
    }
    return '$_selectedFastPrefix$gatewayId';
  }

  /// Sticky Desktop "Fast" mode (`config.set` key=fast).
  Future<bool> readSelectedFast(String? gatewayId) async {
    final v = await _read(_fastKey(gatewayId));
    if (v == null || v.isEmpty) return false;
    return v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'fast';
  }

  Future<void> writeSelectedFast(String gatewayId, bool enabled) =>
      _write(_fastKey(gatewayId), enabled ? '1' : '0');

  String _modelOptionsKey(String gatewayId) =>
      '$_modelOptionsPrefix$gatewayId';

  /// Cached GET /api/model/options catalog (JSON) for instant picker opens.
  Future<String?> readModelOptionsJson(String gatewayId) async {
    final v = await _read(_modelOptionsKey(gatewayId));
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> writeModelOptionsJson(String gatewayId, String json) =>
      _write(_modelOptionsKey(gatewayId), json);

  Future<void> clearModelOptionsCache(String gatewayId) =>
      _delete(_modelOptionsKey(gatewayId));

  Future<void> clearSelectedModel(String? gatewayId) async {
    await _delete(_modelKey(gatewayId));
    await _delete(_providerKey(gatewayId));
    await _delete(_effortKey(gatewayId));
    if (gatewayId == null) {
      await _delete(_legacySelectedModelKey);
    }
  }

  // ── Pinned sessions (Desktop `$pinnedSessionIds`, per gateway) ─────

  String _pinnedKey(String gatewayId) => '$_pinnedSessionsPrefix$gatewayId';

  Future<List<String>> readPinnedSessionIds(String gatewayId) async {
    final raw = await _read(_pinnedKey(gatewayId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final id in decoded)
          if ('$id'.trim().isNotEmpty) '$id'.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> writePinnedSessionIds(String gatewayId, List<String> ids) async {
    // De-dupe, preserve order.
    final seen = <String>{};
    final ordered = <String>[];
    for (final id in ids) {
      final t = id.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      ordered.add(t);
    }
    await _write(_pinnedKey(gatewayId), jsonEncode(ordered));
  }

  Future<List<String>> pinSession(String gatewayId, String sessionId) async {
    final prev = await readPinnedSessionIds(gatewayId);
    if (prev.contains(sessionId)) return prev;
    final next = [...prev, sessionId];
    await writePinnedSessionIds(gatewayId, next);
    return next;
  }

  Future<List<String>> unpinSession(String gatewayId, String sessionId) async {
    final prev = await readPinnedSessionIds(gatewayId);
    final next = prev.where((id) => id != sessionId).toList();
    if (next.length == prev.length) return prev;
    await writePinnedSessionIds(gatewayId, next);
    return next;
  }

  // ── Session read receipts (unread dots in drawer) ──────────────────

  String _sessionReadKey(String gatewayId) => '$_sessionReadPrefix$gatewayId';

  /// Map of sessionId → activity token at last open (usually lastActive).
  Future<Map<String, String>> readSessionReadMap(String gatewayId) async {
    final raw = await _read(_sessionReadKey(gatewayId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if ('${e.key}'.trim().isNotEmpty && '${e.value}'.trim().isNotEmpty)
            '${e.key}'.trim(): '${e.value}'.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> writeSessionReadMap(
    String gatewayId,
    Map<String, String> map,
  ) async {
    await _write(_sessionReadKey(gatewayId), jsonEncode(map));
  }

  Future<Map<String, String>> markSessionRead(
    String gatewayId,
    String sessionId,
    String activityToken,
  ) async {
    final map = await readSessionReadMap(gatewayId);
    map[sessionId] = activityToken;
    await writeSessionReadMap(gatewayId, map);
    return map;
  }

  // ── Legacy password cleanup ───────────────────────────────────────

  String _passwordKey(String gatewayId) => '$_passwordPrefix$gatewayId';

  Future<void> clearPassword(String gatewayId) =>
      _delete(_passwordKey(gatewayId));

  // ── App theme (Desktop skins) ──────────────────────────────────────

  Future<String?> readSkinId() => _read(_skinKey);

  Future<void> writeSkinId(String skinId) => _write(_skinKey, skinId);

  /// `system` | `light` | `dark`
  Future<String?> readThemeMode() => _read(_themeModeKey);

  Future<void> writeThemeMode(String mode) => _write(_themeModeKey, mode);

  /// BCP-47 language tag (`en`, `ja`, `zh`, …) or null to follow the system.
  Future<String?> readLocaleCode() => _read(_localeKey);

  Future<void> writeLocaleCode(String? code) async {
    final v = code?.trim() ?? '';
    if (v.isEmpty) {
      await _delete(_localeKey);
    } else {
      await _write(_localeKey, v);
    }
  }

  /// When true, suppress haptics + completion sounds (Desktop titlebar mute).
  Future<bool> readHapticsMuted() async {
    final raw = await _read(_hapticsMutedKey);
    if (raw == null || raw.isEmpty) return false;
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  Future<void> writeHapticsMuted(bool muted) =>
      _write(_hapticsMutedKey, muted ? '1' : '0');

  String newGatewayId() => _uuid.v4();
}
