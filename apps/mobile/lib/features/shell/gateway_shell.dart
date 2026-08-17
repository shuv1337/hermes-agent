import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/sync/session_touch.dart';
import 'package:hermes_mobile/features/bots/bots_screen.dart';
import 'package:hermes_mobile/features/jobs/jobs_screen.dart';
import 'package:hermes_mobile/features/sessions/sessions_screen.dart';
import 'package:hermes_mobile/features/settings/settings_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

enum GatewayTab { chat, bots, jobs, settings }

List<GatewayTab> gatewayTabsFor({required bool botsAvailable}) => [
  GatewayTab.chat,
  if (botsAvailable) GatewayTab.bots,
  GatewayTab.jobs,
  GatewayTab.settings,
];

/// Bottom nav: Chat | [Bots] | Jobs | Settings.
///
/// Bots is capability-gated by the connected server, so an older gateway or
/// a Hermes install without Bot Mode retains the original three-tab shell.
class GatewayShell extends ConsumerStatefulWidget {
  const GatewayShell({super.key});

  @override
  ConsumerState<GatewayShell> createState() => _GatewayShellState();
}

class _GatewayShellState extends ConsumerState<GatewayShell>
    with WidgetsBindingObserver {
  GatewayTab _tab = GatewayTab.chat;
  StreamSubscription<SessionTouch>? _liveSub;
  StreamSubscription<void>? _stateSub;
  var _live = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootLive());
  }

  Future<void> _bootLive() async {
    final rt = ref.read(gatewayRealtimeProvider);
    if (rt == null) return;
    rt.bindKeepIds(
      () => ref.read(pinnedSessionsProvider).value ?? const <String>[],
    );
    // Prefer ensureLive so chat has a real /api/ws (HTTPS alone is not enough).
    final ok = await rt.ensureLive();
    if (!mounted) return;
    setState(() => _live = ok);
    await _liveSub?.cancel();
    await _stateSub?.cancel();
    _liveSub = rt.sessionTouches.listen(_onSessionTouch);
    _stateSub = rt.stateChanges.listen((_) {
      if (!mounted) return;
      setState(() => _live = rt.isLive);
      // When WS comes back, push any messages saved while "queued".
      if (rt.isLive) {
        unawaited(ref.read(sessionSyncProvider)?.flushPendingOverWs());
      }
    });
    await Future.wait([
      ref.read(sessionsProvider.notifier).softRefresh(),
      ref.read(botsProvider.notifier).refresh(),
      ref.read(jobsProvider.notifier).refresh(),
      // Models: disk cache first (provider build); only soft-diff if empty cold.
      ref.read(modelOptionsProvider.notifier).softSync(forceRefresh: false),
      ref.read(skillsProvider.notifier).refresh(),
    ]);
    if (ok) {
      unawaited(ref.read(sessionSyncProvider)?.flushPendingOverWs());
    }
  }

  void _onSessionTouch(SessionTouch touch) {
    unawaited(ref.read(sessionsProvider.notifier).reloadLocal());
    if (touch.reason == 'poll' ||
        touch.reason == 'complete' ||
        touch.reason == 'connect') {
      unawaited(ref.read(jobsProvider.notifier).refresh());
      unawaited(ref.read(botsProvider.notifier).refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final rt = ref.read(gatewayRealtimeProvider);
    if (rt == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Zombie probe if "open", else force remint+connect. Path watch re-arms.
        unawaited(() async {
          final ok = await rt.onAppResumed();
          if (mounted) setState(() => _live = ok);
          if (ok) {
            unawaited(rt.refreshCaches(reason: 'resume'));
            unawaited(ref.read(sessionSyncProvider)?.flushPendingOverWs());
            unawaited(ref.read(botsProvider.notifier).refresh());
          }
        }());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        rt.onAppPaused();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Warm the gateway graph before tab children watch it. Otherwise the first
    // SessionsScreen frame can flush sessionsProvider while sessionSync is
    // still mounting (null → repo), which invalidates mid-build and trips
    // Riverpod's "setState() during build" assert on ProviderScope.
    ref.watch(sessionSyncProvider);
    ref.watch(gatewayRealtimeProvider);

    final l10n = context.l10n;
    final botsAvailable = ref.watch(botsProvider).value?.available ?? false;
    final tabs = gatewayTabsFor(botsAvailable: botsAvailable);
    final activeTab = tabs.contains(_tab) ? _tab : GatewayTab.chat;
    final selectedIndex = tabs.indexOf(activeTab);
    final page = switch (activeTab) {
      GatewayTab.chat => const SessionsScreen(),
      GatewayTab.bots => const BotsScreen(),
      GatewayTab.jobs => const JobsScreen(),
      GatewayTab.settings => const SettingsScreen(),
    };
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // NavigationBar has a compact default height. Give large accessibility
    // labels room to wrap instead of clipping or overlapping the gesture area.
    final navigationHeight = math.max(80.0, 58.0 + (38.0 * textScale));

    return Scaffold(
      // Do not eagerly build hidden tabs. Besides wasting cold-start work,
      // their TextFields cause Flutter to probe UIPasteboard.hasStrings even
      // though the user has not opened those screens. That API can deadlock
      // the main thread on iOS 27 beta.
      body: page,
      bottomNavigationBar: NavigationBar(
        height: navigationHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          final selected = tabs[i];
          setState(() => _tab = selected);
          if (selected == GatewayTab.chat) {
            unawaited(ref.read(sessionsProvider.notifier).softRefresh());
          }
          if (selected == GatewayTab.bots) {
            unawaited(ref.read(botsProvider.notifier).refresh());
          }
          if (selected == GatewayTab.jobs) {
            unawaited(ref.read(jobsProvider.notifier).refresh());
          }
        },
        destinations: tabs
            .map((tab) {
              return switch (tab) {
                GatewayTab.chat => NavigationDestination(
                  icon: Icon(
                    _live ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  ),
                  selectedIcon: const Icon(Icons.chat_bubble),
                  label: _live ? l10n.navChatLive : l10n.navChat,
                ),
                GatewayTab.bots => NavigationDestination(
                  icon: const Icon(Icons.smart_toy_outlined),
                  selectedIcon: const Icon(Icons.smart_toy),
                  label: l10n.navBots,
                ),
                GatewayTab.jobs => NavigationDestination(
                  icon: const Icon(Icons.schedule_outlined),
                  selectedIcon: const Icon(Icons.schedule),
                  label: l10n.navJobs,
                ),
                GatewayTab.settings => NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: l10n.navSettings,
                ),
              };
            })
            .toList(growable: false),
      ),
    );
  }
}
