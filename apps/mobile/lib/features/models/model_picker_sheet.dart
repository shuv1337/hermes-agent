import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/config/reasoning_effort.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/services/feedback.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Hermes' own effort ladder as picker rows — a compatibility fallback for a
/// gateway that reports a model reasons without naming its legal levels.
/// See [_effortOptionsFor] for exactly when this applies.
final _hermesEffortLadder = <ReasoningEffortOption>[
  for (final effort in kReasoningEffortOptions)
    ReasoningEffortOption(effort: effort),
];

/// Which effort levels the picker offers for [caps].
///
/// Desktop is the proof of what works against a real gateway, and Desktop's
/// capability type has only two fields (`apps/desktop/src/types/hermes.ts:423`
/// `{fast, reasoning}`). It gates its Thinking switch and its hardcoded
/// 7-level ladder on `reasoning` alone
/// (`apps/desktop/src/app/shell/model-edit-submenu.tsx:140,158`,
/// `apps/desktop/src/lib/reasoning-effort.ts:6`).
///
/// The phone must not be stricter than that. A stock Hermes 0.20.2 gateway
/// builds its capability rows as a bare `{"fast": …, "reasoning": …}` — no
/// `thinking` key and no `reasoning_efforts` key for any provider — so any
/// rule keyed off those fields silently renders nothing while Desktop, on the
/// same server, shows the full set of controls. That is the mainstream shape,
/// not a legacy one.
///
/// Server-named levels always win, including an explicitly empty list. They
/// are ordered and carry the provider's own descriptions. Falling back only
/// when the field is absent is safe because
/// every value in it round-trips through the gateway's `parse_reasoning_effort`
/// (`hermes_constants.py`), which falls back to the profile default on an
/// unrecognized level rather than rejecting the request — so the worst case is
/// a level the server quietly ignores, never a 400.
List<ReasoningEffortOption> _effortOptionsFor(ModelCapabilities caps) {
  if (!caps.reasoning) return const [];
  final advertised = caps.reasoningEfforts;
  return advertised ?? _hermesEffortLadder;
}

/// Whether the Thinking switch is offered. Rich gateways are authoritative;
/// the coarse `reasoning` flag is used only when the `thinking` field is
/// absent (the stock Hermes 0.20.2 payload Desktop also supports).
bool _hasThinkingControl(ModelCapabilities caps) =>
    caps.reasoning && (caps.thinking ?? true);

/// Result of a confirmed model picker selection (Desktop model + options).
class ModelPick {
  const ModelPick({
    required this.model,
    this.provider,
    this.reasoningEffort,
    this.reasoningSupported = false,
    this.fastMode,
    this.fastModeSupported = false,
  });

  final String model;
  final String? provider;

  /// Sticky effort (`none` = Thinking off). Null = leave unchanged.
  final String? reasoningEffort;
  final bool reasoningSupported;

  /// Desktop Fast / priority tier. Null = leave unchanged / unsupported.
  final bool? fastMode;

  /// True only when Fast is a request parameter for this model. A `-fast`
  /// sibling is represented by [model] itself and must not receive a
  /// `config.set fast` request.
  final bool fastModeSupported;

  /// Value format Desktop ships to `config.set` / model switch.
  String get configValue {
    final p = provider?.trim();
    if (p == null || p.isEmpty) return model;
    return '$model --provider $p';
  }
}

/// Desktop-parity model picker:
/// 1. Tap a model to *draft* it (does not dismiss)
/// 2. Options (Thinking / Effort / Fast) update for **that** model's capabilities
/// 3. Confirm applies model + options together
Future<ModelPick?> showModelPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  String? sessionId,
  String? initialModel,
  String? initialProvider,
  String? initialReasoningEffort,
  bool? initialFastMode,
  bool showRuntimeOptions = true,
}) {
  unawaited(
    ref
        .read(modelOptionsProvider.notifier)
        .softSync(forceRefresh: true, sessionId: sessionId),
  );
  return showModalBottomSheet<ModelPick>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ModelPickerBody(
      sessionId: sessionId,
      initialModel: initialModel,
      initialProvider: initialProvider,
      initialReasoningEffort: initialReasoningEffort,
      initialFastMode: initialFastMode,
      showRuntimeOptions: showRuntimeOptions,
    ),
  );
}

class _ModelPickerBody extends ConsumerStatefulWidget {
  const _ModelPickerBody({
    this.sessionId,
    this.initialModel,
    this.initialProvider,
    this.initialReasoningEffort,
    this.initialFastMode,
    this.showRuntimeOptions = true,
  });

  final String? sessionId;
  final String? initialModel;
  final String? initialProvider;
  final String? initialReasoningEffort;
  final bool? initialFastMode;
  final bool showRuntimeOptions;

  @override
  ConsumerState<_ModelPickerBody> createState() => _ModelPickerBodyState();
}

class _ModelPickerBodyState extends ConsumerState<_ModelPickerBody> {
  String? _draftModel;
  String? _draftProvider;
  late String _effort;
  var _fast = false;

  @override
  void initState() {
    super.initState();
    _draftModel = widget.initialModel ?? ref.read(selectedModelProvider).value;
    _draftProvider =
        widget.initialProvider ?? ref.read(selectedProviderProvider).value;
    _effort = normalizeReasoningEffort(
      widget.initialReasoningEffort ??
          ref.read(selectedReasoningEffortProvider).value,
    );
    _fast =
        widget.initialFastMode ??
        ref.read(selectedFastModeProvider).value ??
        false;
  }

  /// Desktop: `provider.capabilities?.[modelId]` from /api/model/options.
  ModelCapabilities _capsFor(
    ModelOptionsResult? opts,
    String? model,
    String? provider,
  ) {
    if (opts == null || model == null || model.isEmpty) {
      return const ModelCapabilities(fast: false, reasoning: false);
    }
    // Prefer exact provider slug (same as Desktop group.provider.capabilities).
    if (provider != null && provider.isNotEmpty) {
      for (final p in opts.providers) {
        if (p.slug == provider) return p.capsFor(model);
      }
    }
    for (final p in opts.providers) {
      if (p.models.contains(model)) return p.capsFor(model);
    }
    return const ModelCapabilities(fast: false, reasoning: false);
  }

  FastControl _fastControlFor(
    ModelOptionsResult? opts,
    String? model,
    String? provider,
  ) {
    if (opts == null || model == null || model.trim().isEmpty) {
      return const FastControl.none();
    }
    for (final p in opts.providers) {
      if (provider != null && provider.isNotEmpty && p.slug != provider) {
        continue;
      }
      if (p.models.any((candidate) => candidate.trim() == model.trim())) {
        return resolveFastControl(
          model,
          p.models,
          p.capsFor(model).fast,
          _fast,
        );
      }
    }
    return const FastControl.none();
  }

  String _defaultEffortFor(
    ModelCapabilities caps,
    List<ReasoningEffortOption> options,
  ) {
    final advertised = normalizeReasoningEffort(caps.defaultReasoningEffort);
    if (options.any((option) => option.effort == advertised)) {
      return advertised;
    }
    if (options.any((option) => option.effort == 'medium')) return 'medium';
    return options.isEmpty ? 'medium' : options.first.effort;
  }

  String _resolvedEffortFor(
    ModelCapabilities caps,
    List<ReasoningEffortOption> options, {
    bool preserveThinkingOff = true,
  }) {
    if (!caps.reasoning) return 'none';
    final current = normalizeReasoningEffort(_effort);
    if (_hasThinkingControl(caps) &&
        preserveThinkingOff &&
        !isThinkingEnabled(current)) {
      return 'none';
    }
    if (options.any((option) => option.effort == current)) return current;
    return _defaultEffortFor(caps, options);
  }

  void _selectDraft(
    String modelId,
    String providerSlug,
    ModelCapabilities caps,
  ) {
    hermesHaptic(HapticIntent.selection);
    setState(() {
      final changed = _draftModel != modelId || _draftProvider != providerSlug;
      _draftModel = modelId;
      _draftProvider = providerSlug;
      if (changed) _fast = false;
      // Drop options that this model can't use (Desktop gates the submenu).
      if (!caps.reasoning) {
        _effort = 'none';
      } else {
        final options = _effortOptionsFor(caps);
        _effort = _resolvedEffortFor(caps, options, preserveThinkingOff: false);
      }
      if (!caps.fast) {
        _fast = false;
      }
    });
  }

  void _confirm() {
    final model = _draftModel?.trim();
    if (model == null || model.isEmpty) return;
    hermesHaptic(HapticIntent.submit);
    final opts = ref.read(modelOptionsProvider).value;
    final provider = opts == null
        ? _draftProvider
        : providerForModel(opts, model, preferred: _draftProvider);
    final caps = _capsFor(opts, model, provider);
    final fastControl = _fastControlFor(opts, model, provider);
    final effortOptions = _effortOptionsFor(caps);
    final hasReasoningControl =
        _hasThinkingControl(caps) || effortOptions.isNotEmpty;
    final resolvedEffort = _resolvedEffortFor(caps, effortOptions);
    Navigator.of(context).pop(
      ModelPick(
        model: model,
        provider: provider,
        reasoningEffort: hasReasoningControl ? resolvedEffort : 'none',
        reasoningSupported: hasReasoningControl,
        fastMode: fastControl.kind == FastControlKind.parameter ? _fast : false,
        fastModeSupported: fastControl.kind == FastControlKind.parameter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(modelOptionsProvider);
    final stickyModel = ref.watch(selectedModelProvider).value;
    final stickyProvider = ref.watch(selectedProviderProvider).value;
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    final draftModel = _draftModel ?? stickyModel;
    final optsData = options.asData?.value;
    final draftProvider = optsData == null
        ? (_draftProvider ?? stickyProvider)
        : providerForModel(
            optsData,
            draftModel ?? '',
            preferred: _draftProvider ?? stickyProvider,
          );
    final caps = _capsFor(optsData, draftModel, draftProvider);
    final fastControl = _fastControlFor(optsData, draftModel, draftProvider);
    final effortOptions = _effortOptionsFor(caps);
    final hasThinkingControl = _hasThinkingControl(caps);
    final hasEffortControl = caps.reasoning && effortOptions.isNotEmpty;
    final resolvedEffort = _resolvedEffortFor(caps, effortOptions);
    final waitingCaps = optsData == null && options.isLoading;
    final thinkingOn =
        caps.reasoning &&
        (!hasThinkingControl || isThinkingEnabled(resolvedEffort));
    final canConfirm = draftModel != null && draftModel.trim().isNotEmpty;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.modelPickerTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.modelPickerConfirmHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.refreshModels,
                    onPressed: () => unawaited(
                      ref
                          .read(modelOptionsProvider.notifier)
                          .softSync(
                            forceRefresh: true,
                            sessionId: widget.sessionId,
                          ),
                    ),
                    icon: const Icon(Icons.sync),
                  ),
                ],
              ),
            ),
            // Options for the *draft* model (capability-gated). Profile model
            // pins cannot persist these per-session runtime controls.
            if (widget.showRuntimeOptions)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        draftModel == null || draftModel.isEmpty
                            ? context.l10n.reasoningOptions
                            : '${context.l10n.reasoningOptions} · $draftModel',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (waitingCaps) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.modelCapsLoading,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ] else if (!hasThinkingControl &&
                          !hasEffortControl &&
                          !fastControl.supported) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.modelNoOptions,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                      if (!waitingCaps && hasThinkingControl) ...[
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.l10n.thinking),
                          subtitle: Text(
                            thinkingOn
                                ? context.l10n.thinkingOnHint
                                : context.l10n.thinkingOffHint,
                            style: theme.textTheme.bodySmall,
                          ),
                          value: thinkingOn,
                          onChanged: (on) {
                            hermesHaptic(HapticIntent.selection);
                            setState(() {
                              _effort = on
                                  ? _defaultEffortFor(caps, effortOptions)
                                  : 'none';
                            });
                          },
                        ),
                      ],
                      if (!waitingCaps && thinkingOn && hasEffortControl) ...[
                        Text(
                          context.l10n.effort,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in effortOptions)
                              Tooltip(
                                message: option.description ?? '',
                                child: ChoiceChip(
                                  label: Text(
                                    reasoningEffortFullLabel(option.effort),
                                  ),
                                  selected: resolvedEffort == option.effort,
                                  onSelected: (_) {
                                    hermesHaptic(HapticIntent.selection);
                                    setState(() => _effort = option.effort);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (!waitingCaps && fastControl.supported) ...[
                        if (hasThinkingControl || hasEffortControl)
                          const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.l10n.fastMode),
                          subtitle: Text(
                            context.l10n.fastModeHint,
                            style: theme.textTheme.bodySmall,
                          ),
                          value: fastControl.on,
                          onChanged: (on) {
                            hermesHaptic(HapticIntent.selection);
                            setState(() {
                              _fast = on;
                              if (fastControl.kind == FastControlKind.variant) {
                                _draftModel = on
                                    ? fastControl.fastId
                                    : fastControl.baseId;
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Expanded(
              child: options.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$e', textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => unawaited(
                            ref.read(modelOptionsProvider.notifier).refresh(),
                          ),
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (result) {
                  final providers = result.providers
                      .where((p) => p.models.isNotEmpty)
                      .toList();
                  if (providers.isEmpty) {
                    final dash = ref.read(dashboardClientProvider);
                    final detail = dash?.lastError;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          detail != null && detail.isNotEmpty
                              ? context.l10n.couldNotLoadModels(detail)
                              : context.l10n.noModelsFromGateway,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: providers.length,
                    itemBuilder: (context, i) {
                      final p = providers[i];
                      return _ProviderSection(
                        provider: p,
                        draftModel: draftModel,
                        draftProvider: draftProvider,
                        onSelect: (modelId) =>
                            _selectDraft(modelId, p.slug, p.capsFor(modelId)),
                      );
                    },
                  );
                },
              ),
            ),
            // Confirm / cancel — model is not applied until Confirm.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: canConfirm ? _confirm : null,
                      child: Text(context.l10n.confirmModel),
                    ),
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

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.provider,
    required this.onSelect,
    this.draftModel,
    this.draftProvider,
  });

  final ModelOptionProvider provider;
  final String? draftModel;
  final String? draftProvider;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            provider.name,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (provider.warning != null && provider.warning!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              provider.warning!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (final family in collapseModelFamilies(provider.models))
          Builder(
            builder: (context) {
              final caps = provider.capsFor(family.id);
              final selected =
                  (family.id == draftModel || family.fastId == draftModel) &&
                  (draftProvider == null || draftProvider == provider.slug);
              // Desktop meta: only list options this model actually supports.
              final meta = <String>[
                if (_hasThinkingControl(caps)) context.l10n.thinking,
                if (_effortOptionsFor(caps).isNotEmpty) context.l10n.effort,
                if (caps.fast || family.fastId != null) context.l10n.fastMode,
              ].join(' · ');
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: theme.colorScheme.primary.withValues(
                  alpha: 0.08,
                ),
                title: Text(
                  family.id,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                subtitle: Text(
                  meta.isEmpty ? provider.slug : '${provider.slug} · $meta',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : null,
                onTap: () => onSelect(family.id),
              );
            },
          ),
        const Divider(height: 1),
      ],
    );
  }
}
