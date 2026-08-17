import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Server-backed Bot Mode roster.
///
/// The shell only mounts this screen after the gateway advertises Bot Mode.
/// Polling is scoped to the visible tab so hidden navigation does no work.
class BotsScreen extends ConsumerStatefulWidget {
  const BotsScreen({super.key});

  @override
  ConsumerState<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends ConsumerState<BotsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(ref.read(botsProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bots = ref.watch(botsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.botsTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.sync,
            onPressed: () => ref.read(botsProvider.notifier).refresh(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: bots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _BotsError(error: error),
        data: (view) {
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
                            context.l10n.botsCachedRoster,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: view.profiles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            context.l10n.botsEmpty,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(botsProvider.notifier).refresh(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: view.profiles.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 76),
                          itemBuilder: (context, index) =>
                              _BotTile(bot: view.profiles[index]),
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

class _BotsError extends ConsumerWidget {
  const _BotsError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(botsProvider.notifier).refresh(),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotTile extends StatelessWidget {
  const _BotTile({required this.bot});

  final HermesBotProfile bot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = bot.lastSession;
    final relative = formatSessionRelative(last?.lastActive);
    final preview = last?.preview?.trim();
    final subtitle = preview?.isNotEmpty == true
        ? preview!
        : (bot.description?.trim().isNotEmpty == true
              ? bot.description!.trim()
              : context.l10n.botsNoConversation);
    final accent = _parseColor(bot.color) ?? theme.colorScheme.primaryContainer;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: () => _showBotDetails(context, bot),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: accent,
        foregroundColor:
            ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black87,
        child: Text(
          _initials(bot.displayName),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              bot.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (bot.pinned) ...[
            const SizedBox(width: 6),
            Icon(Icons.push_pin, size: 15, color: theme.colorScheme.primary),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (relative != null) ...[
            const SizedBox(height: 3),
            Text(
              relative,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

Future<void> _showBotDetails(BuildContext context, HermesBotProfile bot) async {
  final theme = Theme.of(context);
  final last = bot.lastSession;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bot.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '@${bot.name == 'default' ? 'hermes' : bot.name}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 18),
            if (bot.description?.trim().isNotEmpty == true) ...[
              Text(bot.description!.trim()),
              const SizedBox(height: 18),
            ],
            _DetailRow(label: context.l10n.modelLabel, value: bot.model),
            _DetailRow(label: context.l10n.provider, value: bot.provider),
            _DetailRow(
              label: context.l10n.lastActivity,
              value: formatSessionRelative(last?.lastActive),
            ),
            _DetailRow(
              label: context.l10n.messagesLabel,
              value: last?.messageCount?.toString(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(child: Text(clean)),
        ],
      ),
    );
  }
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'B';
  if (words.length == 1) return words.first.characters.first.toUpperCase();
  return '${words.first.characters.first}${words.last.characters.first}'
      .toUpperCase();
}

Color? _parseColor(String? raw) {
  if (raw == null) return null;
  final value = raw.trim().replaceFirst('#', '');
  if (value.length != 6 && value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}
