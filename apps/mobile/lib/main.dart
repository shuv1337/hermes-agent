import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hermes_mobile/app.dart';
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
