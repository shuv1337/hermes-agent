import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/sessions/session_chat_screen.dart';

class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.initialJob});

  final HermesJob initialJob;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  late HermesJob _job;
  List<HermesSession> _runs = const [];
  String? _syncError;
  bool _loading = true;
  bool _refreshing = false;
  bool _acting = false;
  Timer? _backstop;
  StreamSubscription? _cronEvents;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_load());
      final realtime = ref.read(gatewayRealtimeProvider);
      _cronEvents = realtime?.events
          .where(
            (event) =>
                event.type == 'cron.changed' ||
                event.type == 'sessions.changed' ||
                event.type == 'background.complete',
          )
          .listen((_) => unawaited(_refresh(silent: true)));
      // Change events are primary. This is the same slow backstop cadence as
      // Desktop on event-capable gateways and only exists while detail is open.
      _backstop = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_refresh(silent: true)),
      );
    });
  }

  @override
  void dispose() {
    _backstop?.cancel();
    _cronEvents?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final local = await ref
          .read(jobsProvider.notifier)
          .loadJobDetail(_job.id);
      if (!mounted) return;
      setState(() {
        _job = local.job;
        _runs = local.runs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    await _refresh(silent: true);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (!silent) _syncError = null;
      });
    }
    try {
      final detail = await ref
          .read(jobsProvider.notifier)
          .refreshJobDetail(_job.id);
      if (!mounted) return;
      setState(() {
        _job = detail.job;
        _runs = detail.runs;
        _syncError = detail.syncError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncError = '$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _act(String action) async {
    if (_acting) return;
    final dash = ref.read(dashboardClientProvider);
    final api = ref.read(hermesApiProvider);
    if (dash == null && api == null) return;
    setState(() => _acting = true);
    try {
      switch (action) {
        case 'run':
          if (dash != null) {
            await dash.runJobNow(_job.id);
          } else {
            await api!.runJobNow(_job.id);
          }
        case 'pause':
          if (dash != null) {
            await dash.pauseJob(_job.id);
          } else {
            await api!.pauseJob(_job.id);
          }
        case 'resume':
          if (dash != null) {
            await dash.resumeJob(_job.id);
          } else {
            await api!.resumeJob(_job.id);
          }
      }
      await ref.read(jobsProvider.notifier).refresh(bypassTtl: true);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _openRun(HermesSession run) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SessionChatScreen(session: run)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _job.enabled == false
        ? 'paused'
        : (_job.lastStatus ?? _job.state ?? 'scheduled');
    return Scaffold(
      appBar: AppBar(
        title: Text(_job.displayName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (_syncError != null) _OfflineBanner(message: _syncError!),
            _HeaderCard(
              job: _job,
              status: status,
              busy: _acting,
              onRun: () => _act('run'),
              onPauseResume: () =>
                  _act(_job.enabled == false ? 'resume' : 'pause'),
            ),
            if (_job.lastError case final error?) ...[
              const SizedBox(height: 12),
              _ErrorCard(label: 'Last run error', message: error),
            ],
            if (_job.lastDeliveryError case final error?) ...[
              const SizedBox(height: 12),
              _ErrorCard(label: 'Delivery error', message: error),
            ],
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Job information',
              children: [
                _InfoRow(label: 'Schedule', value: _job.schedule ?? '—'),
                _InfoRow(label: 'Next run', value: _date(_job.nextRunAt)),
                _InfoRow(label: 'Last run', value: _date(_job.lastRunAt)),
                _InfoRow(label: 'Delivery', value: _job.deliver ?? 'local'),
                if (_job.model != null)
                  _InfoRow(label: 'Model', value: _job.model!),
                if (_job.provider != null)
                  _InfoRow(label: 'Provider', value: _job.provider!),
                if (_job.modelSnapshot != null)
                  _InfoRow(
                    label: 'Created with model',
                    value: _job.modelSnapshot!,
                  ),
                if (_job.providerSnapshot != null)
                  _InfoRow(
                    label: 'Created with provider',
                    value: _job.providerSnapshot!,
                  ),
                if (_job.createdAt != null)
                  _InfoRow(label: 'Created', value: _date(_job.createdAt)),
                if (_job.pausedReason != null)
                  _InfoRow(label: 'Paused because', value: _job.pausedReason!),
                if (_job.skills.isNotEmpty || _job.skill != null)
                  _InfoRow(
                    label: 'Skills',
                    value: _job.skills.isNotEmpty
                        ? _job.skills.join(', ')
                        : _job.skill!,
                  ),
                if (_job.workdir != null)
                  _InfoRow(label: 'Working directory', value: _job.workdir!),
                if (_job.contextFrom != null)
                  _InfoRow(label: 'Context from', value: _job.contextFrom!),
                if (_job.enabledToolsets.isNotEmpty)
                  _InfoRow(
                    label: 'Toolsets',
                    value: _job.enabledToolsets.join(', '),
                  ),
                if (_job.completedRuns != null)
                  _InfoRow(
                    label: 'Completed runs',
                    value: _job.totalRuns == null
                        ? '${_job.completedRuns}'
                        : '${_job.completedRuns} / ${_job.totalRuns}',
                  ),
              ],
            ),
            if ((_job.prompt ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Prompt',
                children: [
                  SelectableText(
                    _job.prompt!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ],
            if ((_job.script ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Script',
                children: [
                  SelectableText(
                    _job.script!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Run history',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_runs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_runs.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_runs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No recorded runs yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var index = 0; index < _runs.length; index++) ...[
                      _RunTile(
                        run: _runs[index],
                        onTap: () => _openRun(_runs[index]),
                      ),
                      if (index != _runs.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _date(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} '
        '(${timeago.format(local)})';
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.job,
    required this.status,
    required this.busy,
    required this.onRun,
    required this.onPauseResume,
  });

  final HermesJob job;
  final String status;
  final bool busy;
  final VoidCallback onRun;
  final VoidCallback onPauseResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(label: Text(status), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onRun,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Run now'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onPauseResume,
                  icon: Icon(
                    job.enabled == false
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 18,
                  ),
                  label: Text(job.enabled == false ? 'Resume' : 'Pause'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.onTap});

  final HermesSession run;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = run.lastActive ?? run.startedAt;
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    return ListTile(
      onTap: onTap,
      leading: Icon(
        run.endedAt == null ? Icons.sync : Icons.check_circle_outline,
      ),
      title: Text(
        run.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (parsed != null) timeago.format(parsed),
          if (run.model != null) run.model,
          if (run.messageCount != null) '${run.messageCount} messages',
        ].whereType<String>().join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SelectableText(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
