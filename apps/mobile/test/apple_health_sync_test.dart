import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:hermes_mobile/core/health/apple_health_sync.dart';

void main() {
  test('HealthKit request covers every coaching category', () {
    final types = AppleHealthSync.types.toSet();

    expect(types.length, AppleHealthSync.types.length);
    expect(
      types,
      containsAll(<HealthDataType>[
        HealthDataType.STEPS,
        HealthDataType.WORKOUT,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.BLOOD_OXYGEN,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.RESPIRATORY_RATE,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_WRIST_TEMPERATURE,
        HealthDataType.DIETARY_ENERGY_CONSUMED,
        HealthDataType.MINDFULNESS,
      ]),
    );
  });
}
