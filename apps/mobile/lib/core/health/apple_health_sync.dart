import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:uuid/uuid.dart';

import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

/// Read-only HealthKit bridge. HealthKit remains the phone-side source of
/// truth; only the incremental cursor is persisted locally. Samples are sent
/// to the user's authenticated Hermes gateway in bounded, idempotent batches.
class AppleHealthSync {
  AppleHealthSync({required this.gatewayId, required this.dashboard});

  final String gatewayId;
  final DashboardClient dashboard;
  final Health _health = Health();

  static const types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.BASAL_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.WEIGHT,
    HealthDataType.BODY_MASS_INDEX,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.HEIGHT,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.WORKOUT,
  ];

  String get _enabledKey => 'hermes_go_health_enabled:$gatewayId';
  String get _cursorKey => 'hermes_go_health_cursor:$gatewayId';
  String get _diagnosticsKey => 'hermes_go_health_diagnostics:$gatewayId';
  final _storage = ConnectionStore.durableSecureStorage();

  Future<bool> get isEnabled async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  Future<void> setEnabled(bool value) async {
    if (value) {
      await _storage.write(key: _enabledKey, value: 'true');
    } else {
      await _storage.delete(key: _enabledKey);
    }
  }

  Future<void> forgetLocalState() async {
    await _storage.delete(key: _enabledKey);
    await _storage.delete(key: _cursorKey);
    await _storage.delete(key: _diagnosticsKey);
  }

  Future<Map<String, int>> get lastReadCounts async {
    final raw = await _storage.read(key: _diagnosticsKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return const {};
    }
  }

  Future<bool> requestReadAuthorization() async {
    if (!Platform.isIOS) return false;
    await _health.configure();
    final granted = await _health.requestAuthorization(
      types,
      permissions: List.filled(types.length, HealthDataAccess.READ),
    );
    if (granted) await setEnabled(true);
    return granted;
  }

  Future<AppleHealthSyncResult> sync({bool initial = false}) async {
    if (!Platform.isIOS || !await isEnabled) {
      return const AppleHealthSyncResult(skipped: true);
    }
    final capability = await dashboard.appleHealthStatus();
    if (capability == null) {
      throw StateError(
        'The Apple Health plugin is not installed on this gateway',
      );
    }
    await _health.configure();
    final now = DateTime.now().toUtc();
    final saved = await _storage.read(key: _cursorKey);
    final cursor = DateTime.tryParse(saved ?? '');
    // One-day overlap catches delayed Watch writes; server UUID upserts make it
    // safe. First consent gets 30 useful days without an enormous history dump.
    final start = initial || cursor == null
        ? now.subtract(const Duration(days: 30))
        : cursor.toUtc().subtract(const Duration(days: 1));
    // Query each type separately. Besides preventing one unavailable HealthKit
    // type from aborting the whole sync, this gives the UI an honest account
    // of what the phone actually returned (HealthKit does not disclose denied
    // read permissions directly).
    final points = <HealthDataPoint>[];
    final readByType = <String, int>{};
    final errors = <String>[];
    for (final type in types) {
      try {
        final values = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: start,
          endTime: now,
        );
        points.addAll(values);
        readByType[type.name] = values.length;
      } catch (error) {
        readByType[type.name] = 0;
        errors.add(type.name);
        debugPrint('AppleHealthSync: could not read ${type.name}: $error');
      }
    }
    var accepted = 0;
    const batchSize = 500;
    for (var offset = 0; offset < points.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, points.length);
      final payload = points
          .sublist(offset, end)
          .map((p) => p.toJson())
          .toList();
      final response = await dashboard.syncAppleHealth({
        'schema_version': 1,
        'device_id': _health.deviceId,
        'batch_id': const Uuid().v4(),
        'app_version': '25',
        'samples': payload,
      });
      accepted += (response['accepted'] as num?)?.toInt() ?? 0;
    }
    await _storage.write(key: _cursorKey, value: now.toIso8601String());
    await _storage.write(key: _diagnosticsKey, value: jsonEncode(readByType));
    debugPrint('AppleHealthSync: ${points.length} read, $accepted accepted');
    return AppleHealthSyncResult(
      read: points.length,
      accepted: accepted,
      readByType: readByType,
      failedTypes: errors,
    );
  }
}

class AppleHealthSyncResult {
  const AppleHealthSyncResult({
    this.read = 0,
    this.accepted = 0,
    this.skipped = false,
    this.readByType = const {},
    this.failedTypes = const [],
  });
  final int read;
  final int accepted;
  final bool skipped;
  final Map<String, int> readByType;
  final List<String> failedTypes;

  int get sleepRead => readByType.entries
      .where((entry) => entry.key.startsWith('SLEEP_'))
      .fold(0, (sum, entry) => sum + entry.value);
}
