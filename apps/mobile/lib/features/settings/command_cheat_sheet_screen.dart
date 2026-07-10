import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Full slash-command registry from the gateway (`GET /api/commands`),
/// searchable and grouped by category — preserving server order.
class CommandCheatSheetScreen extends ConsumerStatefulWidget {
  const CommandCheatSheetScreen({super.key});

  @override
  ConsumerState<CommandCheatSheetScreen> createState() =>
      _CommandCheatSheetScreenState();
}

class _CommandCheatSheetScreenState
    extends ConsumerState<CommandCheatSheetScreen> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commandsAsync = ref.watch(commandsProvider);
    final theme = Theme.of(context);
    final q = _filter.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.commandCheatSheetTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                hintText: context.l10n.filterCommands,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: commandsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.commandsLoadError,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.read(commandsProvider.notifier).refresh(),
                        child: Text(context.l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (list) {
                final filtered = list.where((c) {
                  if (q.isEmpty) return true;
                  return c.name.toLowerCase().contains(q) ||
                      c.aliases.any((a) => a.toLowerCase().contains(q)) ||
                      c.description.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(commandsProvider.notifier).refresh(),
                    child: ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              context.l10n.noCommandsMatch(_filter.text.trim()),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Group by category, preserving server first-seen order.
                final byCat = <String, List<SlashCommand>>{};
                for (final c in filtered) {
                  final cat = c.category.trim().isNotEmpty
                      ? c.category.trim()
                      : context.l10n.commandsSection;
                  byCat.putIfAbsent(cat, () => []).add(c);
                }
                final cats = byCat.keys.toList();

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(commandsProvider.notifier).refresh(),
                  child: ListView.builder(
                    itemCount: cats.fold<int>(
                      0,
                      (n, c) => n + 1 + byCat[c]!.length,
                    ),
                    itemBuilder: (context, index) {
                      var i = 0;
                      for (final cat in cats) {
                        if (i == index) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              cat,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }
                        i++;
                        for (final c in byCat[cat]!) {
                          if (i == index) {
                            return _CommandTile(command: c);
                          }
                          i++;
                        }
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({required this.command});

  final SlashCommand command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: const Icon(Icons.terminal),
      title: Text(
        command.slashCommand,
        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (command.description.trim().isNotEmpty)
              Text(command.description.trim()),
            if (command.aliases.isNotEmpty ||
                command.cliOnly ||
                command.configGated)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final alias in command.aliases)
                      _CommandChip(
                        label: '/$alias',
                        background: theme.colorScheme.surfaceContainerHighest,
                        foreground: theme.colorScheme.onSurfaceVariant,
                      ),
                    if (command.cliOnly)
                      _CommandChip(
                        label: context.l10n.commandBadgeCli,
                        background: theme.colorScheme.secondaryContainer,
                        foreground: theme.colorScheme.onSecondaryContainer,
                      ),
                    if (command.configGated)
                      _CommandChip(
                        label: context.l10n.commandBadgeConfigGated,
                        background: theme.colorScheme.tertiaryContainer,
                        foreground: theme.colorScheme.onTertiaryContainer,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
