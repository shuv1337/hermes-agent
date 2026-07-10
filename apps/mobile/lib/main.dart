import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/core/services/result_notifier.dart';
import 'package:hermes_mobile/core/sync/background_sync.dart';

Future<void> main() async {
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
  // Init plugin early; prompt on first Settings→Notifications or first notify.
  try {
    await ResultNotifier.instance.init(requestPermission: false);
  } catch (e) {
    debugPrint('ResultNotifier early init failed: $e');
  }
  // Background flush/pull + local notifications for agent/job results.
  // Failures here must not block app boot (e.g. tests / missing plugins).
  try {
    await BackgroundSync.initialize();
  } catch (e) {
    debugPrint('BackgroundSync.initialize failed: $e');
  }
  runApp(const HermesMobileApp());
}
