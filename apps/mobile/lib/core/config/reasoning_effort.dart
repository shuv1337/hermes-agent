/// Desktop-parity reasoning effort levels (VALID_REASONING_EFFORTS).
///
/// Desktop UI: Thinking toggle + Minimal / Low / Medium / High / Max.
/// Gateway: `config.set` key=`reasoning` value=`none|minimal|low|medium|high|xhigh`.
library;

/// How Desktop exposes a model's Fast control.
enum FastControlKind { none, parameter, variant }

class FastControl {
  const FastControl.none()
    : kind = FastControlKind.none,
      baseId = null,
      fastId = null,
      on = false;

  const FastControl.parameter({required this.on})
    : kind = FastControlKind.parameter,
      baseId = null,
      fastId = null;

  const FastControl.variant({
    required this.baseId,
    required this.fastId,
    required this.on,
  }) : kind = FastControlKind.variant;

  final FastControlKind kind;
  final String? baseId;
  final String? fastId;
  final bool on;

  bool get supported => kind != FastControlKind.none;
}

/// Resolve the same Fast behavior as Desktop:
/// parameter support wins; otherwise a `model-fast` sibling is a toggle.
FastControl resolveFastControl(
  String model,
  Iterable<String> providerModels,
  bool parameterSupported,
  bool currentFastMode,
) {
  final id = model.trim();
  final models = providerModels
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toSet();
  if (parameterSupported) {
    return FastControl.parameter(on: currentFastMode);
  }

  final fastSuffix = RegExp(r'-fast$', caseSensitive: false);
  if (fastSuffix.hasMatch(id)) {
    final base = id.replaceFirst(fastSuffix, '');
    if (models.contains(base)) {
      return FastControl.variant(baseId: base, fastId: id, on: true);
    }
    return const FastControl.none();
  }

  final fastId = '$id-fast';
  if (models.contains(fastId)) {
    return FastControl.variant(baseId: id, fastId: fastId, on: false);
  }

  // A carried-over parameter can still be turned off after switching to a
  // model whose catalog no longer advertises Fast support.
  if (currentFastMode) {
    return const FastControl.parameter(on: true);
  }
  return const FastControl.none();
}

class ModelFamily {
  const ModelFamily({required this.id, this.fastId});

  final String id;
  final String? fastId;
}

/// Collapse a base model and its `-fast` sibling into one Desktop-style row.
List<ModelFamily> collapseModelFamilies(Iterable<String> models) {
  final ids = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
  final present = ids.toSet();
  final consumed = <String>{};
  final families = <ModelFamily>[];
  final fastSuffix = RegExp(r'-fast$', caseSensitive: false);

  for (final id in ids) {
    if (consumed.contains(id)) continue;
    if (fastSuffix.hasMatch(id) &&
        present.contains(id.replaceFirst(fastSuffix, ''))) {
      continue;
    }
    final fastId = present.contains('$id-fast')
        ? '$id-fast'
        : (present.contains('$id-FAST') ? '$id-FAST' : null);
    families.add(ModelFamily(id: id, fastId: fastId));
    consumed.add(id);
    if (fastId != null) consumed.add(fastId);
  }
  return families;
}

/// Legacy fallback for gateways that predate per-model effort metadata.
const kReasoningEffortOptions = <String>[
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

/// Normalize raw gateway/UI value to a known token.
String normalizeReasoningEffort(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty) return 'medium'; // Hermes default
  if (v == 'maximum') return 'max';
  if (v == 'off' || v == 'disabled') return 'none';
  if (v == 'none' || v == 'ultra' || kReasoningEffortOptions.contains(v)) {
    return v;
  }
  return 'medium';
}

bool isThinkingEnabled(String? effort) =>
    normalizeReasoningEffort(effort) != 'none';

/// Short label for the model chip (Desktop: "Grok 4.5 · Med").
String reasoningEffortShortLabel(String? effort) {
  switch (normalizeReasoningEffort(effort)) {
    case 'none':
      return 'Off';
    case 'minimal':
      return 'Min';
    case 'low':
      return 'Low';
    case 'medium':
      return 'Med';
    case 'high':
      return 'High';
    case 'xhigh':
      return 'XHigh';
    case 'max':
      return 'Max';
    case 'ultra':
      return 'Ultra';
    default:
      return 'Med';
  }
}

/// Full label for the effort radio list.
String reasoningEffortFullLabel(String effort) {
  switch (normalizeReasoningEffort(effort)) {
    case 'none':
      return 'Off';
    case 'minimal':
      return 'Minimal';
    case 'low':
      return 'Low';
    case 'medium':
      return 'Medium';
    case 'high':
      return 'High';
    case 'xhigh':
      return 'Extra high';
    case 'max':
      return 'Max';
    case 'ultra':
      return 'Ultra';
    default:
      return effort;
  }
}

/// Model chip: `model · Med` / `model · Med · Fast` or bare model.
String modelChipLabel(String model, String? effort, {bool fast = false}) {
  final m = model.trim();
  if (m.isEmpty || m.toLowerCase() == 'select model') return m;
  final parts = <String>[m];
  final e = normalizeReasoningEffort(effort);
  if (e != 'none') {
    parts.add(reasoningEffortShortLabel(e));
  } else {
    parts.add('Off');
  }
  if (fast) parts.add('Fast');
  return parts.join(' · ');
}
