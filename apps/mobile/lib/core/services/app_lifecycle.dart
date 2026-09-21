import 'package:flutter/widgets.dart';

/// Lightweight global app lifecycle for notification decisions.
///
/// Registered from [HermesMobileApp] / shell; safe if never attached
/// (defaults to resumed).
class AppLifecycle {
  AppLifecycle._();

  static AppLifecycleState _state = AppLifecycleState.resumed;

  static AppLifecycleState get state => _state;

  static bool get isForeground =>
      _state == AppLifecycleState.resumed ||
      _state == AppLifecycleState.inactive;

  static bool get isBackground =>
      _state == AppLifecycleState.paused ||
      _state == AppLifecycleState.hidden ||
      _state == AppLifecycleState.detached;

  static void update(AppLifecycleState state) {
    _state = state;
  }
}
