import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // BGTaskScheduler requires a native launch handler for every identifier
    // listed in Info.plist *before* Dart schedules the task. Without this,
    // registerPeriodicTask crashes:
    //   NSInternalInconsistencyException:
    //   No launch handler registered for task with identifier …
    // Identifiers must match BackgroundTasks.* unique names in Dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "hermes.mobile.periodicSync",
      frequency: NSNumber(value: 15 * 60)
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "hermes.mobile.oneOffSync"
    )

    // Keep black under Flutter while the engine boots (matches LaunchScreen).
    window?.backgroundColor = .black

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
