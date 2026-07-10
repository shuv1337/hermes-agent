import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/sync/background_sync.dart';
import 'package:hermes_mobile/core/services/result_notifier.dart';

/// Foreground job reconciliation — same snapshot file as background sync.
class JobNotifierService {
  Future<void> init() => ResultNotifier.instance.init();

  /// Compare current jobs to previous snapshot; notify on completed/failed.
  Future<void> reconcile(List<HermesJob> jobs, {required String gatewayId}) {
    return BackgroundSync.reconcileJobsPublic(jobs, gatewayId: gatewayId);
  }
}
