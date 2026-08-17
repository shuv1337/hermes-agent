import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/bots/bot_avatar.dart';
import 'package:hermes_mobile/features/bots/bot_cronjobs_sheet.dart';
import 'package:hermes_mobile/features/bots/bot_sessions_sheet.dart';
import 'package:hermes_mobile/features/bots/create_bot_sheet.dart';
import 'package:hermes_mobile/features/bots/edit_bot_sheet.dart';
import 'package:hermes_mobile/features/sessions/session_chat_screen.dart';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(ref.read(botsProvider.notifier).refresh());
      });
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
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
            tooltip: context.l10n.createBotAction,
            onPressed: _createBot,
            icon: const Icon(Icons.add),
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
                child: RefreshIndicator(
                  onRefresh: () => ref.read(botsProvider.notifier).refresh(),
                  child: view.profiles.isEmpty
                      ? CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    context.l10n.botsEmpty,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
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

  Future<void> _createBot() async {
    final existing = ref.read(botsProvider).value?.profiles ?? const [];
    final created = await showCreateBotSheet(
      context,
      existingNames: {for (final bot in existing) bot.name},
    );
    if (!mounted || created == null) return;
    await ref.read(botsProvider.notifier).refresh();
    if (!mounted) return;
    await _openBotChat(context, ref, created);
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

class _BotTile extends ConsumerWidget {
  const _BotTile({required this.bot});

  final HermesBotProfile bot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last = bot.lastSession;
    final relative = formatSessionRelative(last?.lastActive);
    final preview = last?.preview?.trim();
    final subtitle = preview?.isNotEmpty == true
        ? preview!
        : (bot.description?.trim().isNotEmpty == true
              ? bot.description!.trim()
              : context.l10n.botsNoConversation);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: () => _openBotChat(context, ref, bot),
      onLongPress: () => _editBot(context, ref, bot),
      leading: BotAvatar(bot: bot),
      title: Row(
        children: [
          Flexible(
            child: Text(
              bot.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (bot.showsHandle) ...[
            const SizedBox(width: 7),
            Text(
              '@${bot.handle}',
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Sessions',
            onPressed: () => showBotSessionsSheet(context, bot: bot),
            icon: const Icon(Icons.forum_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Bot actions',
            onSelected: (action) {
              switch (action) {
                case 'cronjobs':
                  unawaited(showBotCronjobsSheet(context, bot: bot));
                case 'edit':
                  unawaited(_editBot(context, ref, bot));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'cronjobs',
                child: ListTile(
                  leading: Icon(Icons.event_repeat_outlined),
                  title: Text('Cronjobs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(context.l10n.editBotAction),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

Future<void> _editBot(
  BuildContext context,
  WidgetRef ref,
  HermesBotProfile bot,
) async {
  final saved = await showEditBotSheet(context, bot: bot);
  if (!saved || !context.mounted) return;
  await ref.read(botsProvider.notifier).refresh();
}

Future<void> _openBotChat(
  BuildContext context,
  WidgetRef ref,
  HermesBotProfile bot,
) async {
  final sync = ref.read(sessionSyncProvider);
  if (sync == null) return;
  try {
    final target = await sync.openBotChat(bot);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SessionChatScreen(
          session: target.session,
          profileName: bot.name,
          initialMessage: target.created
              ? 'Hey, tell me about yourself!'
              : null,
        ),
      ),
    );
    if (context.mounted) {
      unawaited(ref.read(botsProvider.notifier).refresh());
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}
