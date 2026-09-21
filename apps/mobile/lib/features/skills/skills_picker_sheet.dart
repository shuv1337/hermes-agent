import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/services/feedback.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Pick an installed skill → returns the slash command to run
/// (e.g. `/gif-search`). Optional instruction is appended by the caller.
Future<String?> showSkillsPickerSheet(BuildContext context, WidgetRef ref) {
  ref.read(skillsProvider.notifier).refresh();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _SkillsPickerBody(),
  );
}

class _SkillsPickerBody extends ConsumerStatefulWidget {
  const _SkillsPickerBody();

  @override
  ConsumerState<_SkillsPickerBody> createState() => _SkillsPickerBodyState();
}

class _SkillsPickerBodyState extends ConsumerState<_SkillsPickerBody> {
  final _filter = TextEditingController();
  var _reloading = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _reloading = true);
    try {
      final msg = await ref.read(skillsProvider.notifier).reloadFromGateway();
      hermesHaptic(HapticIntent.success);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      FeedbackService.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.reloadFailed('$e'))));
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skills = ref.watch(skillsProvider);
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    final q = _filter.text.trim().toLowerCase();

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.skillsSection,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.skillsPickerSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.reloadSkills,
                      onPressed: _reloading ? null : _reload,
                      icon: _reloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: _filter,
                  decoration: InputDecoration(
                    hintText: context.l10n.filterSkills,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: skills.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('$e', textAlign: TextAlign.center),
                    ),
                  ),
                  data: (list) {
                    final filtered = list.where((s) {
                      if (q.isEmpty) return true;
                      return s.name.toLowerCase().contains(q) ||
                          (s.description?.toLowerCase().contains(q) ?? false) ||
                          (s.category?.toLowerCase().contains(q) ?? false);
                    }).toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            list.isEmpty
                                ? context.l10n.noSkillsCached
                                : context.l10n.noSkillsMatch(
                                    _filter.text.trim(),
                                  ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    // Group by category.
                    final byCat = <String, List<HermesSkill>>{};
                    for (final s in filtered) {
                      final cat = (s.category?.trim().isNotEmpty == true)
                          ? s.category!.trim()
                          : context.l10n.skillsSection;
                      byCat.putIfAbsent(cat, () => []).add(s);
                    }
                    final cats = byCat.keys.toList()..sort();

                    return ListView.builder(
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
                          for (final s in byCat[cat]!) {
                            if (i == index) {
                              return _SkillTile(
                                skill: s,
                                onTap: () {
                                  hermesHaptic(HapticIntent.selection);
                                  Navigator.pop(context, s.slashCommand);
                                },
                              );
                            }
                            i++;
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.skill, required this.onTap});

  final HermesSkill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = !skill.enabled;
    return ListTile(
      enabled: skill.enabled,
      onTap: skill.enabled ? onTap : null,
      leading: Icon(
        Icons.extension_outlined,
        color: dim
            ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
            : theme.colorScheme.primary,
      ),
      title: Text(
        skill.slashCommand,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: dim
              ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
              : null,
        ),
      ),
      subtitle: Text(
        [
          if (skill.description?.trim().isNotEmpty == true)
            skill.description!.trim(),
          if (skill.provenance != null) skill.provenance!,
          if (!skill.enabled) 'disabled',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }
}
