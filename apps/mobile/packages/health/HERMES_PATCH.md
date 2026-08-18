# Hermes Health plugin patch

This is `health` 13.3.1 with a narrow iOS safety patch in
`HealthDataReader.swift`.

Before converting an `HKQuantity` into the unit requested by the Dart package,
the reader checks that the units are compatible. HealthKit raises an
Objective-C exception for incompatible conversions; that exception crosses the
Flutter method channel and aborts the entire app before Dart can catch it.
Incompatible samples are now skipped and logged without recording their value.

Hermes Go uses this package only for Apple HealthKit. Its Android plugin
registration is intentionally removed so Android builds neither bundle Health
Connect code nor inherit the upstream plugin's Android 26 minimum SDK.
