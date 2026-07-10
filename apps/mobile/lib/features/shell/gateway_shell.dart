import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/sync/session_touch.dart';
import 'package:hermes_mobile/features/jobs/jobs_screen.dart';
import 'package:hermes_mobile/features/sessions/sessions_screen.dart';
import 'package:hermes_mobile/features/settings/settings_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Bottom nav: Chat | Jobs | Settings.
class GatewayShell extends ConsumerStatefulWidget {
  const GatewayShell({super.key});

  @override
  ConsumerState<GatewayShell> createState() => _GatewayShellState();
}

class _GatewayShellState extends ConsumerState<GatewayShell>
    with WidgetsBindingObserver {
  int _tab = 0;
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
    final l10n = context.l10n;
    final pages = const [SessionsScreen(), JobsScreen(), SettingsScreen()];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // NavigationBar has a compact default height. Give large accessibility
    // labels room to wrap instead of clipping or overlapping the gesture area.
    final navigationHeight = math.max(80.0, 58.0 + (38.0 * textScale));

    return Scaffold(
      // Do not eagerly build hidden tabs. Besides wasting cold-start work,
      // their TextFields cause Flutter to probe UIPasteboard.hasStrings even
      // though the user has not opened those screens. That API can deadlock
      // the main thread on iOS 27 beta.
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        height: navigationHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) {
            unawaited(ref.read(sessionsProvider.notifier).softRefresh());
          }
          if (i == 1) ref.read(jobsProvider.notifier).refresh();
        },
        destinations: [
          NavigationDestination(
            icon: Icon(_live ? Icons.chat_bubble : Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: _live ? l10n.navChatLive : l10n.navChat,
          ),
          NavigationDestination(
            icon: const Icon(Icons.schedule_outlined),
            selectedIcon: const Icon(Icons.schedule),
            label: l10n.navJobs,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
