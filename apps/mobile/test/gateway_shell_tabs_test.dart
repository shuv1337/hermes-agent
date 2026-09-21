import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/features/shell/gateway_shell.dart';

void main() {
  test('Bot Mode inserts Bots between Chat and Jobs', () {
    expect(gatewayTabsFor(botsAvailable: true), const [
      GatewayTab.chat,
      GatewayTab.bots,
      GatewayTab.jobs,
      GatewayTab.settings,
    ]);
  });

  test('unsupported servers retain the original navigation', () {
    expect(gatewayTabsFor(botsAvailable: false), const [
      GatewayTab.chat,
      GatewayTab.jobs,
      GatewayTab.settings,
    ]);
  });
}
