import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';
import 'package:hermes_mobile/features/models/model_picker_sheet.dart';

enum BotAdvancedTab { general, capabilities }

class BotAdvancedController extends ChangeNotifier {
  BotAdvancedController.create() : isCreate = true;
  BotAdvancedController.edit() : isCreate = false;

  final bool isCreate;
  final soul = TextEditingController();
  bool expanded = false;
  BotAdvancedTab tab = BotAdvancedTab.general;
  String? cloneFrom = 'default';
  bool shareAuth = true;
  bool noSkills = false;
  String model = '';
  String provider = '';
  bool loading = false;
  String? error;
  List<BotCapabilityOption> skills = const [];
  List<BotCapabilityOption> toolsets = const [];
  List<BotCapabilityOption> mcpServers = const [];
  bool dirtySoul = false;
  bool dirtyModel = false;
  bool dirtySkills = false;
  bool dirtyToolsets = false;
  bool dirtyMcp = false;
  String? _loadedProfile;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    soul.dispose();
    super.dispose();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  void setTab(BotAdvancedTab value) {
    tab = value;
    changed();
  }

  void setSoul(String value) {
    dirtySoul = true;
    changed();
  }

  void setModel(ModelPick pick) {
    model = pick.model;
    provider = pick.provider ?? '';
    dirtyModel = true;
    changed();
  }

  Future<void> open(
    SessionSyncRepository sync, {
    required String profile,
  }) async {
    expanded = !expanded;
    changed();
    if (expanded) await load(sync, profile: profile, seedGeneral: !isCreate);
  }

  Future<void> setCloneFrom(SessionSyncRepository sync, String? value) async {
    cloneFrom = value;
    if (value != null) noSkills = false;
    _loadedProfile = null;
    changed();
    await load(sync, profile: value ?? 'default', seedGeneral: false);
  }

  Future<void> load(
    SessionSyncRepository sync, {
    required String profile,
    required bool seedGeneral,
  }) async {
    if (loading || _loadedProfile == profile) return;
    loading = true;
    error = null;
    changed();
    try {
      final result = await sync.describeBotProfile(profile);
      if (_disposed) return;
      skills = result.skills;
      toolsets = result.toolsets;
      mcpServers = result.mcpServers;
      if (seedGeneral) {
        soul.text = result.soul;
        model = result.model;
        provider = result.provider;
        dirtySoul = false;
        dirtyModel = false;
      }
      dirtySkills = false;
      dirtyToolsets = false;
      dirtyMcp = false;
      _loadedProfile = profile;
    } catch (e) {
      if (!_disposed) error = '$e';
    } finally {
      if (!_disposed) {
        loading = false;
        changed();
      }
    }
  }

  void toggle(String kind, int index, bool enabled) {
    switch (kind) {
      case 'skills':
        skills = _replace(skills, index, enabled);
        dirtySkills = true;
      case 'toolsets':
        toolsets = _replace(toolsets, index, enabled);
        dirtyToolsets = true;
      case 'mcp':
        mcpServers = _replace(mcpServers, index, enabled);
        dirtyMcp = true;
    }
    changed();
  }

  List<BotCapabilityOption> _replace(
    List<BotCapabilityOption> source,
    int index,
    bool enabled,
  ) => [
    for (var i = 0; i < source.length; i++)
      i == index ? source[i].copyWith(enabled: enabled) : source[i],
  ];

  List<String>? get disabledSkills => dirtySkills
      ? skills.where((item) => !item.enabled).map((item) => item.name).toList()
      : null;

  List<String>? get enabledToolsets {
    if (!dirtyToolsets) return null;
    final enabled = toolsets.where((item) => item.enabled).toList();
    if (enabled.isEmpty || enabled.length == toolsets.length) return const [];
    return enabled.map((item) => item.name).toList();
  }

  List<String>? get enabledMcpServers => dirtyMcp
      ? mcpServers
            .where((item) => item.enabled)
            .map((item) => item.name)
            .toList()
      : null;
}

class BotAdvancedEditor extends ConsumerWidget {
  const BotAdvancedEditor({
    super.key,
    required this.controller,
    required this.profile,
    required this.profileNames,
    required this.enabled,
  });

  final BotAdvancedController controller;
  final String profile;
  final Set<String> profileNames;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sync = ref.read(sessionSyncProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: !enabled || sync == null
                  ? null
                  : () => unawaited(
                      controller.open(
                        sync,
                        profile: controller.isCreate ? 'default' : profile,
                      ),
                    ),
              icon: Icon(
                controller.expanded ? Icons.expand_more : Icons.chevron_right,
              ),
              label: const Text(
                'Advanced · model, persona, skills, tools, MCP',
              ),
            ),
            if (controller.expanded) ...[
              const SizedBox(height: 6),
              SegmentedButton<BotAdvancedTab>(
                segments: const [
                  ButtonSegment(
                    value: BotAdvancedTab.general,
                    label: Text('General'),
                    icon: Icon(Icons.tune),
                  ),
                  ButtonSegment(
                    value: BotAdvancedTab.capabilities,
                    label: Text('Capabilities'),
                    icon: Icon(Icons.extension_outlined),
                  ),
                ],
                selected: {controller.tab},
                onSelectionChanged: enabled
                    ? (selection) => controller.setTab(selection.single)
                    : null,
              ),
              const SizedBox(height: 12),
              if (controller.loading)
                const LinearProgressIndicator()
              else if (controller.error != null)
                _ErrorCard(
                  message: controller.error!,
                  onRetry: sync == null
                      ? null
                      : () => unawaited(
                          controller.load(
                            sync,
                            profile: controller.isCreate
                                ? controller.cloneFrom ?? 'default'
                                : profile,
                            seedGeneral: !controller.isCreate,
                          ),
                        ),
                )
              else if (controller.tab == BotAdvancedTab.general)
                _general(context, ref, sync)
              else
                _capabilities(context),
            ],
          ],
        );
      },
    );
  }

  Widget _general(
    BuildContext context,
    WidgetRef ref,
    SessionSyncRepository? sync,
  ) {
    final modelLabel = controller.model.isEmpty
        ? 'Inherited from ${controller.isCreate ? controller.cloneFrom ?? 'a fresh profile' : 'profile'}'
        : '${controller.model}${controller.provider.isEmpty ? '' : ' · ${controller.provider}'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isCreate) ...[
          DropdownButtonFormField<String>(
            initialValue: controller.cloneFrom ?? '__fresh__',
            decoration: const InputDecoration(labelText: 'Clone from profile'),
            items: [
              const DropdownMenuItem(
                value: '__fresh__',
                child: Text('Fresh profile · bundled skills'),
              ),
              for (final name in {'default', ...profileNames}.toList()..sort())
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: !enabled || sync == null || controller.noSkills
                ? null
                : (value) => unawaited(
                    controller.setCloneFrom(
                      sync,
                      value == '__fresh__' ? null : value,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.smart_toy_outlined),
          title: const Text('Model'),
          subtitle: Text(modelLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: !enabled
              ? null
              : () async {
                  final pick = await showModelPickerSheet(
                    context,
                    ref,
                    initialModel: controller.model.isEmpty
                        ? null
                        : controller.model,
                    initialProvider: controller.provider.isEmpty
                        ? null
                        : controller.provider,
                    showRuntimeOptions: false,
                  );
                  if (pick != null) controller.setModel(pick);
                },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.soul,
          enabled: enabled,
          minLines: 5,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'SOUL.md${controller.isCreate ? ' · optional' : ''}',
            alignLabelWithHint: true,
            helperText: controller.isCreate
                ? 'Leave blank to generate a persona from the name, title, and description.'
                : 'This is the bot’s complete persona and persistent instructions.',
          ),
          onChanged: controller.setSoul,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        if (controller.isCreate) ...[
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: controller.shareAuth,
            onChanged: enabled
                ? (value) {
                    controller.shareAuth = value;
                    controller.changed();
                  }
                : null,
            title: const Text('Share keys & accounts'),
            subtitle: const Text(
              'Keep subscriptions, OAuth logins, and API keys shared with the main profile.',
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: controller.noSkills,
            onChanged: enabled
                ? (value) {
                    controller.noSkills = value;
                    if (value) controller.cloneFrom = null;
                    controller.changed();
                  }
                : null,
            title: const Text('Create empty'),
            subtitle: const Text('Skip bundled skills.'),
          ),
        ],
      ],
    );
  }

  Widget _capabilities(BuildContext context) {
    if (controller.skills.isEmpty &&
        controller.toolsets.isEmpty &&
        controller.mcpServers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('This profile did not report configurable capabilities.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.noSkills && controller.isCreate)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Create empty is enabled, so bundled skills will be skipped. Tool and MCP choices still apply.',
              ),
            ),
          ),
        _CapabilitySection(
          title: 'Skills',
          icon: Icons.auto_awesome_outlined,
          items: controller.skills,
          enabled: enabled && !controller.noSkills,
          onChanged: (index, value) =>
              controller.toggle('skills', index, value),
        ),
        _CapabilitySection(
          title: 'Tools',
          icon: Icons.build_outlined,
          items: controller.toolsets,
          enabled: enabled,
          onChanged: (index, value) =>
              controller.toggle('toolsets', index, value),
        ),
        _CapabilitySection(
          title: 'MCP servers',
          icon: Icons.hub_outlined,
          items: controller.mcpServers,
          enabled: enabled,
          onChanged: (index, value) => controller.toggle('mcp', index, value),
        ),
      ],
    );
  }
}

class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.icon,
    required this.items,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<BotCapabilityOption> items;
  final bool enabled;
  final void Function(int index, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('${items.where((item) => item.enabled).length} enabled'),
      children: [
        for (var index = 0; index < items.length; index++)
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.only(left: 16),
            dense: true,
            value: items[index].enabled,
            onChanged: enabled ? (value) => onChanged(index, value) : null,
            title: Text(
              items[index].label.isEmpty
                  ? items[index].name
                  : items[index].label,
            ),
            subtitle:
                (items[index].description.isEmpty &&
                    items[index].detail.isEmpty)
                ? null
                : Text(
                    [
                      items[index].description,
                      items[index].detail,
                    ].where((part) => part.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(message),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
