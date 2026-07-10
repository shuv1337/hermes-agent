import 'package:flutter/material.dart';

import 'package:hermes_mobile/core/models/context_usage.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Desktop-parity context usage panel (segment bar + category list).
Future<void> showContextUsageSheet(
  BuildContext context, {
  required Future<ContextBreakdown> Function() load,
  UsageStats? seedUsage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ContextUsageBody(load: load, seedUsage: seedUsage),
  );
}

class _ContextUsageBody extends StatefulWidget {
  const _ContextUsageBody({required this.load, this.seedUsage});

  final Future<ContextBreakdown> Function() load;
  final UsageStats? seedUsage;

  @override
  State<_ContextUsageBody> createState() => _ContextUsageBodyState();
}

class _ContextUsageBodyState extends State<_ContextUsageBody> {
  ContextBreakdown? _breakdown;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _breakdown = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final seed = widget.seedUsage;
    final b = _breakdown;
    final used = b?.contextUsed ?? seed?.contextUsed ?? 0;
    final max = b?.contextMax ?? seed?.contextMax ?? 0;
    final pct = (b?.contextPercent ?? seed?.contextPercent ?? 0)
        .clamp(0, 100)
        .round();
    final categories = b?.categories ?? const <ContextUsageCategory>[];
    final segmentTotal =
        categories.fold<int>(0, (s, c) => s + c.tokens).clamp(1, 1 << 30);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.contextUsageTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (max > 0)
                  Text(
                    l10n.contextUsageTokenSummary(
                      '~${compactTokenCount(used)}',
                      compactTokenCount(max),
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: l10n.sync,
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.sync, size: 20),
                ),
              ],
            ),
            if (max > 0) ...[
              const SizedBox(height: 4),
              Text(
                l10n.contextUsagePercentFull(pct),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _SegmentBar(categories: categories, total: segmentTotal),
              const SizedBox(height: 16),
            ],
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.contextUsageLoading,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '$_error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.contextUsageEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    final color = c.resolveColor(theme.colorScheme);
                    return Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _localizedCategory(l10n, c),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          compactTokenCount(c.tokens),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _localizedCategory(AppLocalizations l10n, ContextUsageCategory c) {
    switch (c.id) {
      case 'system_prompt':
        return l10n.contextCatSystemPrompt;
      case 'tool_definitions':
        return l10n.contextCatToolDefinitions;
      case 'rules':
        return l10n.contextCatRules;
      case 'skills':
        return l10n.contextCatSkills;
      case 'mcp':
        return l10n.contextCatMcp;
      case 'subagent_definitions':
        return l10n.contextCatSubagents;
      case 'memory':
        return l10n.contextCatMemory;
      case 'conversation':
        return l10n.contextCatConversation;
      default:
        return c.label;
    }
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.categories, required this.total});

  final List<ContextUsageCategory> categories;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (categories.isEmpty) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (final c in categories)
              Flexible(
                flex: (c.tokens * 1000 / total).round().clamp(1, 100000),
                child: Container(color: c.resolveColor(theme.colorScheme)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact context chip for the session header (Desktop status-bar gauge).
class ContextUsageChip extends StatelessWidget {
  const ContextUsageChip({
    super.key,
    required this.usage,
    this.breakdown,
    this.onTap,
  });

  final UsageStats? usage;
  final ContextBreakdown? breakdown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = breakdown?.contextUsed ?? usage?.contextUsed ?? 0;
    final max = breakdown?.contextMax ?? usage?.contextMax ?? 0;
    final pct =
        (breakdown?.contextPercent ?? usage?.contextPercent ?? 0).round().clamp(
          0,
          100,
        );
    final label = max > 0
        ? '${compactTokenCount(used)}/${compactTokenCount(max)}'
        : (usage != null && usage!.total > 0
              ? '${compactTokenCount(usage!.total)} tok'
              : '—');

    final cats = breakdown?.categories ?? const <ContextUsageCategory>[];
    final segmentTotal =
        cats.fold<int>(0, (s, c) => s + c.tokens).clamp(1, 1 << 30);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.data_usage,
                    size: 14,
                    color: theme.colorScheme.primary.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (max > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$pct%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (max > 0) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: 120,
                  child: _SegmentBar(
                    categories: cats.isNotEmpty
                        ? cats
                        : [
                            ContextUsageCategory(
                              id: 'conversation',
                              label: 'used',
                              tokens: used.clamp(1, 1 << 30),
                            ),
                          ],
                    total: cats.isNotEmpty
                        ? segmentTotal
                        : (used.clamp(1, 1 << 30)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
