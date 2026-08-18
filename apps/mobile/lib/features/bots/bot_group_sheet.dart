import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';

Future<void> showBotGroupSheet(
  BuildContext context, {
  required HermesBotProfile bot,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BotGroupSheet(bot: bot),
  );
}

class _BotGroupSheet extends ConsumerStatefulWidget {
  const _BotGroupSheet({required this.bot});

  final HermesBotProfile bot;

  @override
  ConsumerState<_BotGroupSheet> createState() => _BotGroupSheetState();
}

class _BotGroupSheetState extends ConsumerState<_BotGroupSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _assign(String? group) async {
    if (_busy) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sync.updateBotGroup(widget.bot, group);
      await ref.read(botsProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final profiles = ref.watch(botsProvider).value?.profiles ?? const [];
    final groups = {
      for (final bot in profiles)
        if (bot.group?.trim().isNotEmpty == true) bot.group!.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final current = widget.bot.group?.trim() ?? '';

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Move to group', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Groups become labeled sections in the Bots roster and sync to every Hermes client.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in groups)
                    ChoiceChip(
                      label: Text(group),
                      selected: group == current,
                      onSelected: _busy ? null : (_) => _assign(group),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: !_busy,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: groups.isEmpty ? 'Group name' : 'New group',
                      hintText: groups.isEmpty ? 'e.g. Research' : null,
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) _assign(value);
                    },
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final value = _name.text.trim();
                          if (value.isNotEmpty) _assign(value);
                        },
                  child: const Text('Create'),
                ),
              ],
            ),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _assign(null),
                  icon: const Icon(Icons.folder_off_outlined),
                  label: Text('Remove from “$current”'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
