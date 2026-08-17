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
    final points = await _health.getHealthDataFromTypes(
      types: types,
      startTime: start,
      endTime: now,
    );
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
        'app_version': '21',
        'samples': payload,
      });
      accepted += (response['accepted'] as num?)?.toInt() ?? 0;
    }
    await _storage.write(key: _cursorKey, value: now.toIso8601String());
    debugPrint('AppleHealthSync: ${points.length} read, $accepted accepted');
    return AppleHealthSyncResult(read: points.length, accepted: accepted);
  }
}

class AppleHealthSyncResult {
  const AppleHealthSyncResult({
    this.read = 0,
    this.accepted = 0,
    this.skipped = false,
  });
  final int read;
  final int accepted;
  final bool skipped;
}
