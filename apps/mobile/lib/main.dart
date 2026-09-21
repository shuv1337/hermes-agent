import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/network/secure_storage_gate.dart';
import 'package:hermes_mobile/core/sync/background_sync.dart';

Future<void> main() async {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // Match launch screen: avoid white flash between splash and first Flutter frame.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const HermesMobileApp());
  // Plugin/OS registrations happen after the first frame: nothing below is
  // needed to paint the first screen. Workmanager.initialize spawns a whole
  // second headless Flutter engine and the notifications plugin does
  // platform-channel permission probing — awaiting those before runApp
  // blocked cold start for seconds on device. ResultNotifier methods lazily
  // init themselves, and BackgroundSync.initialize runs ResultNotifier.init
  // internally, so deferring loses nothing.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint(
      'Startup: first Flutter frame in ${startup.elapsedMilliseconds}ms',
    );
    unawaited(_initBackgroundServices(startup));
  });
}

Future<void> _initBackgroundServices(Stopwatch startup) async {
  // Wait for the first gateway-book read to settle before spawning
  // Workmanager's headless engine: doing both concurrently can wedge the
  // secure-storage platform channel and hang boot on the root spinner
  // forever. The timeout keeps background services alive even if no
  // readBook ever runs on some future boot path.
  try {
    await ConnectionStore.firstReadSettled.timeout(
      const Duration(seconds: 10),
    );
    // Boot does a burst of keychain ops (book, cookies, mirror re-seed).
    // Wait for the whole burst to drain, not just the first read — spawning
    // Workmanager's engine mid-burst wedges the channel (~30s on device).
    await SecureStorageGate.whenIdle().timeout(const Duration(seconds: 10));
  } catch (_) {}
  // Background flush/pull + local notifications for agent/job results.
  // Failures here must not block the app (e.g. tests / missing plugins).
  try {
    final backgroundInit = Stopwatch()..start();
    await BackgroundSync.initialize();
    debugPrint(
      'Startup: deferred background services ready in '
      '${backgroundInit.elapsedMilliseconds}ms '
      '(${startup.elapsedMilliseconds}ms since process start)',
    );
  } catch (e) {
    debugPrint('BackgroundSync.initialize failed: $e');
  }
}
