import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Cron / scheduled jobs on the host agent.
/// Local-first cache; network errors keep the last known list.
class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.jobsTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.sync,
            onPressed: () =>
                ref.read(jobsProvider.notifier).refresh(bypassTtl: true),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.read(jobsProvider.notifier).refresh(bypassTtl: true),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (view) {
          final list = view.jobs;
          return Column(
            children: [
              if (view.syncError != null)
                Material(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.55,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            view.syncError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(jobsProvider.notifier)
                              .refresh(bypassTtl: true),
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                view.syncError != null
                                    ? context.l10n.noCachedJobs
                                    : context.l10n.noCronJobs,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => ref
                                    .read(jobsProvider.notifier)
                                    .refresh(bypassTtl: true),
                                child: Text(context.l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(jobsProvider.notifier)
                            .refresh(bypassTtl: true),
                        child: ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 16),
                          itemBuilder: (context, i) => _JobTile(job: list[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});

  final HermesJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // `enabled == false` must win over `lastStatus`/`state`: a paused job
    // keeps whatever status its last *run* finished with (e.g. "success"),
    // but that's stale information about a run that happened before it was
    // paused — the row needs to reflect the job's current (paused) state,
    // not its history, or pausing/resuming never visibly changes anything.
    final status = job.enabled == false
        ? 'paused'
        : (job.lastStatus ?? job.state ?? 'scheduled');
    final when = _rel(job.lastRunAt ?? job.nextRunAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        job.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          if (job.schedule != null) job.schedule,
          status,
          ?when,
          if (job.deliver != null) '→ ${job.deliver}',
        ].whereType<String>().join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final dash = ref.read(dashboardClientProvider);
          final api = ref.read(hermesApiProvider);
          try {
            switch (v) {
              case 'run':
                if (dash != null) {
                  await dash.runJobNow(job.id);
                } else if (api != null) {
                  await api.runJobNow(job.id);
                }
              case 'pause':
                if (dash != null) {
                  await dash.pauseJob(job.id);
                } else if (api != null) {
                  await api.pauseJob(job.id);
                }
              case 'resume':
                if (dash != null) {
                  await dash.resumeJob(job.id);
                } else if (api != null) {
                  await api.resumeJob(job.id);
                }
            }
            await ref.read(jobsProvider.notifier).refresh(bypassTtl: true);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'run', child: Text(context.l10n.runNow)),
          PopupMenuItem(value: 'pause', child: Text(context.l10n.pause)),
          PopupMenuItem(value: 'resume', child: Text(context.l10n.resume)),
        ],
      ),
      leading: Icon(_iconFor(status), color: _colorFor(theme, status)),
    );
  }

  IconData _iconFor(String status) {
    final s = status.toLowerCase();
    if (s.contains('run')) return Icons.play_circle_outline;
    if (s.contains('fail') || s.contains('error')) return Icons.error_outline;
    if (s.contains('pause') || s.contains('disabled')) {
      return Icons.pause_circle_outline;
    }
    if (s.contains('complete') || s.contains('success')) {
      return Icons.check_circle_outline;
    }
    return Icons.schedule;
  }

  Color _colorFor(ThemeData theme, String status) {
    final s = status.toLowerCase();
    if (s.contains('fail') || s.contains('error')) {
      return theme.colorScheme.error;
    }
    if (s.contains('complete') || s.contains('success')) {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.onSurface.withValues(alpha: 0.5);
  }

  String? _rel(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return timeago.format(dt.toLocal());
  }
}
