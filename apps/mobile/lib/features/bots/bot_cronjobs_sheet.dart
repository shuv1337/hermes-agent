import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/jobs/job_detail_screen.dart';

Future<void> showBotCronjobsSheet(
  BuildContext context, {
  required HermesBotProfile bot,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BotCronjobsSheet(bot: bot),
  );
}

class _BotCronjobsSheet extends ConsumerStatefulWidget {
  const _BotCronjobsSheet({required this.bot});

  final HermesBotProfile bot;

  @override
  ConsumerState<_BotCronjobsSheet> createState() => _BotCronjobsSheetState();
}

class _BotCronjobsSheetState extends ConsumerState<_BotCronjobsSheet> {
  var _loading = true;
  var _busy = false;
  Object? _error;
  List<HermesJob> _jobs = const [];

  String get _tag => '[bot:${widget.bot.name.toLowerCase()}] ';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final sync = ref.read(sessionSyncProvider);
      if (sync == null) throw StateError('Gateway is not connected');
      final result = await sync.gatewayRequest('cron.manage', {
        'action': 'list',
        'include_disabled': true,
        'profile': widget.bot.name,
      });
      final raw = result['jobs'];
      final jobs = raw is List
          ? raw
                .whereType<Map>()
                .map((row) => HermesJob.fromJson(row.cast<String, dynamic>()))
                .where(
                  (job) =>
                      job.id.isNotEmpty &&
                      (job.name ?? '').toLowerCase().startsWith(_tag),
                )
                .toList(growable: false)
          : const <HermesJob>[];
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateBotCronjobSheet(bot: widget.bot),
    );
    if (created == true) {
      await _load();
      ref.read(jobsProvider.notifier).refresh(bypassTtl: true);
    }
  }

  Future<void> _act(HermesJob job, String action) async {
    if (_busy) return;
    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete cronjob?'),
          content: Text('Delete “${_title(job)}”?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      if (action == 'run') {
        final dashboard = ref.read(dashboardClientProvider);
        if (dashboard == null) throw StateError('Dashboard is not connected');
        await dashboard.runJobNow(job.id);
      } else {
        final sync = ref.read(sessionSyncProvider);
        if (sync == null) throw StateError('Gateway is not connected');
        await sync.gatewayRequest('cron.manage', {
          'action': action,
          'name': job.id,
          'profile': widget.bot.name,
        });
      }
      await _load();
      ref.read(jobsProvider.notifier).refresh(bypassTtl: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _title(HermesJob job) {
    final name = job.displayName;
    return name.toLowerCase().startsWith(_tag)
        ? name.substring(_tag.length)
        : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.bot.displayName} cronjobs',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          '@${widget.bot.handle} · runs use this bot’s profile and history',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create cronjob',
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading && _jobs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _jobs.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.5,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(28),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.event_repeat_outlined,
                                            size: 42,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _error == null
                                                ? 'No cronjobs yet. Create a recurring task for this bot.'
                                                : 'Could not load cronjobs\n$_error',
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 14),
                                          FilledButton.icon(
                                            onPressed: _error == null
                                                ? _create
                                                : _load,
                                            icon: Icon(
                                              _error == null
                                                  ? Icons.add
                                                  : Icons.refresh,
                                            ),
                                            label: Text(
                                              _error == null
                                                  ? 'Create cronjob'
                                                  : 'Retry',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _jobs.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, indent: 56),
                              itemBuilder: (context, index) {
                                final job = _jobs[index];
                                final active =
                                    job.enabled != false &&
                                    job.state?.toLowerCase() != 'paused';
                                final next = DateTime.tryParse(
                                  job.nextRunAt ?? '',
                                );
                                return ListTile(
                                  leading: Icon(
                                    active
                                        ? Icons.schedule
                                        : Icons.pause_circle_outline,
                                    color: active
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(_title(job)),
                                  subtitle: Text(
                                    [
                                      job.schedule,
                                      active ? 'active' : 'paused',
                                      if (active && next != null)
                                        'next ${timeago.format(next.toLocal())}',
                                    ].whereType<String>().join(' · '),
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          JobDetailScreen(initialJob: job),
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_busy,
                                    onSelected: (action) => _act(job, action),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'run',
                                        child: Text('Run now'),
                                      ),
                                      PopupMenuItem(
                                        value: active ? 'pause' : 'resume',
                                        child: Text(
                                          active ? 'Pause' : 'Resume',
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateBotCronjobSheet extends ConsumerStatefulWidget {
  const _CreateBotCronjobSheet({required this.bot});

  final HermesBotProfile bot;

  @override
  ConsumerState<_CreateBotCronjobSheet> createState() =>
      _CreateBotCronjobSheetState();
}

class _CreateBotCronjobSheetState
    extends ConsumerState<_CreateBotCronjobSheet> {
  final _name = TextEditingController();
  final _instruction = TextEditingController();
  final _number = TextEditingController(text: '2');
  final _repeat = TextEditingController();
  final _advanced = TextEditingController();
  var _frequency = 'daily';
  var _unit = 'h';
  var _weekday = 1;
  var _monthday = 1;
  var _time = const TimeOfDay(hour: 9, minute: 0);
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _instruction.dispose();
    _number.dispose();
    _repeat.dispose();
    _advanced.dispose();
    super.dispose();
  }

  bool get _needsTime =>
      const {'daily', 'weekdays', 'weekly', 'monthly'}.contains(_frequency);

  String get _schedule {
    final n = int.tryParse(_number.text) ?? 1;
    return switch (_frequency) {
      'once' => '${n.clamp(1, 9999)}$_unit',
      'hourly' => 'every 1h',
      'daily' => '${_time.minute} ${_time.hour} * * *',
      'weekdays' => '${_time.minute} ${_time.hour} * * 1-5',
      'weekly' => '${_time.minute} ${_time.hour} * * $_weekday',
      'monthly' => '${_time.minute} ${_time.hour} $_monthday * *',
      'interval' => 'every ${n.clamp(1, 9999)}$_unit',
      _ => _advanced.text.trim(),
    };
  }

  Future<void> _submit() async {
    final title = _name.text.trim();
    final prompt = _instruction.text.trim();
    if (title.isEmpty || prompt.isEmpty || _schedule.isEmpty) {
      setState(() => _error = 'Name, instruction, and schedule are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sync = ref.read(sessionSyncProvider);
      if (sync == null) throw StateError('Gateway is not connected');
      final repeat = int.tryParse(_repeat.text.trim());
      await sync.gatewayRequest('cron.manage', {
        'action': 'add',
        'name': '[bot:${widget.bot.name}] $title',
        'schedule': _schedule,
        'prompt': prompt,
        'profile': widget.bot.name,
        if (_frequency != 'once' && repeat != null && repeat > 0)
          'repeat': repeat,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final frequencies = const {
      'once': 'Once, in…',
      'hourly': 'Every hour',
      'daily': 'Every day',
      'weekdays': 'Weekdays',
      'weekly': 'Every week',
      'monthly': 'Every month',
      'interval': 'Interval',
      'advanced': 'Advanced…',
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New cronjob', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'A recurring task ${widget.bot.displayName} runs on a schedule. Runs land in its own history.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Name this cronjob',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instruction,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Instruction',
                hintText: 'What should this cronjob do each time it runs?',
              ),
            ),
            const SizedBox(height: 16),
            Text('When to run', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    items: frequencies.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _frequency = value!),
                  ),
                ),
                if (_needsTime) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _time,
                              );
                              if (picked != null) {
                                setState(() => _time = picked);
                              }
                            },
                      child: Text(_time.format(context)),
                    ),
                  ),
                ],
              ],
            ),
            if (_frequency == 'weekly') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Monday')),
                  DropdownMenuItem(value: 2, child: Text('Tuesday')),
                  DropdownMenuItem(value: 3, child: Text('Wednesday')),
                  DropdownMenuItem(value: 4, child: Text('Thursday')),
                  DropdownMenuItem(value: 5, child: Text('Friday')),
                  DropdownMenuItem(value: 6, child: Text('Saturday')),
                  DropdownMenuItem(value: 0, child: Text('Sunday')),
                ],
                onChanged: (value) => setState(() => _weekday = value!),
                decoration: const InputDecoration(labelText: 'Day'),
              ),
            ],
            if (_frequency == 'monthly') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _monthday,
                items: List.generate(
                  31,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('Day ${index + 1}'),
                  ),
                ),
                onChanged: (value) => setState(() => _monthday = value!),
              ),
            ],
            if (_frequency == 'once' || _frequency == 'interval') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _number,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Every'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      items: const [
                        DropdownMenuItem(value: 'm', child: Text('Minutes')),
                        DropdownMenuItem(value: 'h', child: Text('Hours')),
                        DropdownMenuItem(value: 'd', child: Text('Days')),
                      ],
                      onChanged: (value) => setState(() => _unit = value!),
                    ),
                  ),
                ],
              ),
            ],
            if (_frequency == 'advanced') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _advanced,
                decoration: const InputDecoration(
                  labelText: 'Schedule',
                  hintText: 'every 2h or 0 9 * * *',
                ),
              ),
            ],
            if (_frequency != 'once' && _frequency != 'advanced') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _repeat,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stop after',
                  hintText: 'Blank = forever',
                  suffixText: 'runs',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _schedule.isEmpty ? 'Enter a schedule' : _schedule,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.event_repeat),
              label: Text(_busy ? 'Scheduling…' : 'Create cronjob'),
            ),
          ],
        ),
      ),
    );
  }
}
