import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'package:hermes_mobile/core/db/app_database.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/connection_store.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/network/hermes_api.dart';
import 'package:hermes_mobile/core/services/result_notifier.dart';
import 'package:hermes_mobile/core/health/apple_health_sync.dart';
import 'package:hermes_mobile/core/sync/gateway_realtime.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';
import 'package:hermes_mobile/core/sync/watch_store.dart';

/// Background task names (must stay stable for OS registration).
///
/// **Not** the primary session update path. Desktop uses a live `/api/ws`
/// JSON-RPC socket ([GatewayRealtime]). Workmanager here is only a
/// last-resort catch-up when iOS/Android has killed the process — Android's
/// minimum periodic interval is 15 minutes, which is why that number appears.
class BackgroundTasks {
  static const uniquePeriodicName = 'hermes.mobile.periodicSync';
  static const periodicTask = 'hermes.periodicSync';
  static const oneOffTask = 'hermes.oneOffSync';
  static const oneOffUnique = 'hermes.mobile.oneOffSync';
}

/// Entry point for Workmanager isolates — keep top-level + pragma.
@pragma('vm:entry-point')
void hermesBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Background isolates need binding for path_provider / plugins.
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final result = await BackgroundSync.run(reason: taskName);
      debugPrint('Hermes background sync ($taskName): $result');
      return true;
    } catch (e, st) {
      debugPrint('Hermes background sync failed: $e\n$st');
      return false;
    }
  });
}

class BackgroundSync {
  static bool _initialized = false;

  /// Register OS background scheduling. Safe to call on every cold start.
  ///
  /// iOS: AppDelegate must call WorkmanagerPlugin.registerPeriodicTask /
  /// registerBGProcessingTask for [BackgroundTasks.uniquePeriodicName] and
  /// [BackgroundTasks.oneOffUnique] or iOS will abort on schedule.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await ResultNotifier.instance.init(requestPermission: false);
    } catch (e) {
      debugPrint('ResultNotifier.init failed: $e');
    }

    try {
      await Workmanager().initialize(hermesBackgroundDispatcher);
    } catch (e) {
      debugPrint('Workmanager.initialize failed: $e');
      return;
    }

    // Android min period is 15 minutes; iOS decides actual cadence.
    // uniqueName MUST match AppDelegate + Info.plist BGTask identifiers.
    try {
      await Workmanager().registerPeriodicTask(
        BackgroundTasks.uniquePeriodicName,
        BackgroundTasks.periodicTask,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('registerPeriodicTask failed: $e');
    }
    _initialized = true;
  }

  /// Kick a sooner one-off sync (e.g. user backgrounded after send).
  static Future<void> scheduleSoon({Duration delay = Duration.zero}) async {
    try {
      await Workmanager().registerOneOffTask(
        BackgroundTasks.oneOffUnique,
        BackgroundTasks.oneOffTask,
        initialDelay: delay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('scheduleSoon failed: $e');
    }
  }

  /// Full background pass: flush outbox, pull watches, jobs, notify results.
  static Future<String> run({String reason = 'manual'}) async {
    final store = ConnectionStore();
    final book = await store.readBook();
    final profile = book.resolved;
    if (profile == null) {
      return 'no-gateway';
    }

    final dashboard = DashboardClient(profile: profile);
    final api = profile.hasLegacyToken
        ? HermesApi(baseUrl: profile.baseUrl, apiKey: profile.apiKey)
        : null;
    final db = AppDatabase();
    final watchStore = WatchStore();
    final notifier = ResultNotifier.instance;
    await notifier.init(requestPermission: false);

    var notified = 0;
    var flushedOps = 0;
    try {
      try {
        await dashboard.status();
      } catch (_) {
        if (api == null) return 'offline';
        try {
          await api.health();
        } catch (_) {
          return 'offline';
        }
      }

      final sync = SessionSyncRepository(
        gatewayId: profile.id,
        db: db,
        dashboard: dashboard,
        api: api,
      );

      final pendingBefore = await db.pendingOpsForGateway(profile.id);

      // REST outbox flush — only does anything under legacy API-key auth
      // (flushOutbox() no-ops without a HermesApi client).
      await sync.flushOutbox();

      // Cookie/session auth — the only mode ConnectionScreen produces — has
      // no API key, so the REST flush above never runs anything and these
      // ops used to sit in the outbox until the user reopened the app and
      // the WS reconnected there. Mint a short-lived ticket off the
      // persisted session cookies (same mechanism GatewayRealtime uses in
      // the foreground — see gateway_realtime.dart `_resolveWsUrl`) and
      // connect just long enough for that connect's own success hook
      // (`flushPendingOverWs`, fired from `_connectOnceBody`) to drain the
      // queue, then tear the socket back down. This is the one-shot
      // background counterpart of reopening the app.
      if ((await db.pendingOpsForGateway(profile.id)).isNotEmpty) {
        GatewayRealtime? realtime;
        try {
          realtime = GatewayRealtime(profile: profile, sessionSync: sync);
          sync.bindRealtime(realtime);
          final connected = await realtime.ensureLive().timeout(
            const Duration(seconds: 25),
            onTimeout: () => false,
          );
          if (connected) {
            // ensureLive()'s connect-success path already kicked off
            // flushPendingOverWs() (fire-and-forget) — wait for it to
            // actually drain instead of racing it with a second call here
            // (flushPendingOverWs's own _flushing guard would just no-op
            // ours and we'd have no handle on the real one to await).
            final deadline = DateTime.now().add(const Duration(seconds: 45));
            while (DateTime.now().isBefore(deadline)) {
              if ((await db.pendingOpsForGateway(profile.id)).isEmpty) break;
              await Future<void>.delayed(const Duration(seconds: 2));
            }
          }
        } catch (e) {
          debugPrint('BackgroundSync: WS catch-up flush failed: $e');
        } finally {
          sync.bindRealtime(null);
          await realtime?.dispose();
        }
      }

      final pendingAfter = await db.pendingOpsForGateway(profile.id);
      flushedOps = (pendingBefore.length - pendingAfter.length).clamp(0, 9999);

      await sync.syncSessions();

      // HealthKit remains authoritative; this is an opportunistic incremental
      // upload when the user has explicitly enabled a Health Coach bot.
      try {
        await AppleHealthSync(
          gatewayId: profile.id,
          dashboard: dashboard,
        ).sync();
      } catch (e) {
        debugPrint('BackgroundSync: Apple Health sync skipped: $e');
      }

      final activeWatches = await watchStore.forGateway(profile.id);
      for (final watch in activeWatches) {
        final msgs = await sync.syncMessages(watch.sessionId);
        HermesMessage? result;
        if (msgs.length > watch.baselineMessageCount) {
          for (var i = msgs.length - 1; i >= watch.baselineMessageCount; i--) {
            if (msgs[i].isAssistant) {
              result = msgs[i];
              break;
            }
          }
        }

        if (result != null) {
          final preview = (result.content ?? '').trim();
          final body = preview.isEmpty
              ? 'Agent finished a turn'
              : (preview.length > 160
                    ? '${preview.substring(0, 160)}…'
                    : preview);
          await notifier.showSessionResult(
            sessionId: watch.sessionId,
            title: watch.title?.trim().isNotEmpty == true
                ? watch.title!
                : 'Hermes ready',
            body: body,
          );
          await watchStore.unwatch(profile.id, watch.sessionId);
          notified++;
        }
      }

      try {
        List<HermesJob> jobs;
        try {
          jobs = await dashboard.listCronJobs();
        } catch (_) {
          jobs = api == null ? const [] : await api.listJobs();
        }
        notified += await reconcileJobsPublic(jobs, gatewayId: profile.id);
      } catch (_) {}

      if (notified == 0 && flushedOps > 0) {
        await notifier.showSyncSummary(
          title: 'Hermes synced',
          body: flushedOps == 1
              ? '1 pending action sent to your gateway'
              : '$flushedOps pending actions sent to your gateway',
        );
        notified++;
      }

      return 'ok notified=$notified flushed=$flushedOps '
          'watches=${activeWatches.length} reason=$reason';
    } finally {
      await db.close();
    }
  }

  /// Shared by foreground Jobs tab and background worker.
  static Future<int> reconcileJobsPublic(
    List<HermesJob> jobs, {
    required String gatewayId,
  }) async {
    final snapStore = _JobStatusSnapshotStore();
    final prev = await snapStore.read(gatewayId);
    final next = <String, String>{};
    var count = 0;

    for (final job in jobs) {
      final status = (job.lastStatus ?? job.state ?? '').toLowerCase();
      next[job.id] = status;
      final old = prev[job.id];
      if (old == null || old == status) continue;
      if (!_isTerminal(status)) continue;
      await ResultNotifier.instance.showJobResult(
        jobId: job.id,
        title: _isFailure(status) ? 'Hermes job failed' : 'Hermes job finished',
        body: '${job.displayName}: $status',
      );
      count++;
    }
    await snapStore.write(gatewayId, next);
    return count;
  }

  static bool _isTerminal(String status) {
    final s = status.toLowerCase();
    return s.contains('complete') ||
        s.contains('success') ||
        s.contains('ok') ||
        s.contains('done') ||
        s.contains('finish') ||
        s.contains('fail') ||
        s.contains('error') ||
        s.contains('cancel') ||
        status == 'done';
  }

  static bool _isFailure(String status) {
    return status.contains('fail') || status.contains('error');
  }
}

class _JobStatusSnapshotStore {
  Future<File> _file(String gatewayId) async {
    final dir = await getApplicationSupportDirectory();
    final safe = gatewayId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${dir.path}/job_status_$safe.json');
  }

  Future<Map<String, String>> read(String gatewayId) async {
    try {
      final f = await _file(gatewayId);
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return {};
      return raw.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> write(String gatewayId, Map<String, String> snap) async {
    final f = await _file(gatewayId);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(snap), flush: true);
  }
}
