import 'package:flutter/material.dart';

/// Desktop `UsageStats` / session.info `usage` payload (partial).
class UsageStats {
  const UsageStats({
    this.input = 0,
    this.output = 0,
    this.reasoning = 0,
    this.total = 0,
    this.calls = 0,
    this.contextUsed,
    this.contextMax,
    this.contextPercent,
    this.model,
  });

  final int input;
  final int output;
  final int reasoning;
  final int total;
  final int calls;
  final int? contextUsed;
  final int? contextMax;
  final double? contextPercent;
  final String? model;

  bool get hasContextGauge =>
      (contextMax ?? 0) > 0 && (contextUsed ?? 0) >= 0;

  factory UsageStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UsageStats();
    int asInt(dynamic v) {
      if (v is num) return v.round();
      return int.tryParse('$v') ?? 0;
    }

    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    return UsageStats(
      input: asInt(json['input'] ?? json['prompt']),
      output: asInt(json['output'] ?? json['completion']),
      reasoning: asInt(json['reasoning']),
      total: asInt(json['total']),
      calls: asInt(json['calls']),
      contextUsed: json.containsKey('context_used')
          ? asInt(json['context_used'])
          : null,
      contextMax: json.containsKey('context_max')
          ? asInt(json['context_max'])
          : null,
      contextPercent: asDouble(json['context_percent']),
      model: json['model']?.toString(),
    );
  }

  UsageStats merge(UsageStats other) {
    return UsageStats(
      input: other.input != 0 ? other.input : input,
      output: other.output != 0 ? other.output : output,
      reasoning: other.reasoning != 0 ? other.reasoning : reasoning,
      total: other.total != 0 ? other.total : total,
      calls: other.calls != 0 ? other.calls : calls,
      contextUsed: other.contextUsed ?? contextUsed,
      contextMax: other.contextMax ?? contextMax,
      contextPercent: other.contextPercent ?? contextPercent,
      model: (other.model != null && other.model!.isNotEmpty)
          ? other.model
          : model,
    );
  }
}

class ContextUsageCategory {
  const ContextUsageCategory({
    required this.id,
    required this.label,
    required this.tokens,
    this.colorHex,
  });

  final String id;
  final String label;
  final int tokens;
  final String? colorHex;

  factory ContextUsageCategory.fromJson(Map<String, dynamic> json) {
    return ContextUsageCategory(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? json['id'] ?? ''}',
      tokens: json['tokens'] is num
          ? (json['tokens'] as num).round()
          : int.tryParse('${json['tokens']}') ?? 0,
      colorHex: json['color']?.toString(),
    );
  }

  Color resolveColor(ColorScheme scheme) {
    return categoryColor(id, scheme);
  }
}

class ContextBreakdown {
  const ContextBreakdown({
    this.categories = const [],
    this.contextMax = 0,
    this.contextUsed = 0,
    this.contextPercent = 0,
    this.estimatedTotal = 0,
    this.model,
  });

  final List<ContextUsageCategory> categories;
  final int contextMax;
  final int contextUsed;
  final double contextPercent;
  final int estimatedTotal;
  final String? model;

  bool get hasData =>
      contextMax > 0 || contextUsed > 0 || categories.isNotEmpty;

  factory ContextBreakdown.fromJson(Map<String, dynamic> json) {
    final raw = json['categories'];
    final cats = <ContextUsageCategory>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          cats.add(
            ContextUsageCategory.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }
    double pct = 0;
    final p = json['context_percent'];
    if (p is num) {
      pct = p.toDouble();
    } else if (p != null) {
      pct = double.tryParse('$p') ?? 0;
    }
    int asInt(dynamic v) {
      if (v is num) return v.round();
      return int.tryParse('$v') ?? 0;
    }

    return ContextBreakdown(
      categories: cats,
      contextMax: asInt(json['context_max']),
      contextUsed: asInt(json['context_used']),
      contextPercent: pct,
      estimatedTotal: asInt(json['estimated_total']),
      model: json['model']?.toString(),
    );
  }
}

/// Flutter colors matching Desktop context usage segments.
Color categoryColor(String id, ColorScheme scheme) {
  switch (id) {
    case 'system_prompt':
      return const Color(0xFF6B7280);
    case 'tool_definitions':
      return const Color(0xFFA78BFA);
    case 'rules':
      return const Color(0xFF34D399);
    case 'skills':
      return const Color(0xFFF59E0B);
    case 'mcp':
      return const Color(0xFFEC4899);
    case 'subagent_definitions':
      return const Color(0xFF3B82F6);
    case 'memory':
      return const Color(0xFFF97316);
    case 'conversation':
      return const Color(0xFF0D9488);
    default:
      return scheme.outline;
  }
}

/// Desktop-style compact token count (`42.9k`, `131.1k`).
String compactTokenCount(num value) {
  final n = value.toDouble().abs();
  if (n < 1000) return value.round().toString();
  if (n < 10000) {
    final k = n / 1000;
    return '${k.toStringAsFixed(1)}k';
  }
  if (n < 1000000) {
    final k = n / 1000;
    // One decimal under 100k, whole otherwise (matches ~42.9k / 131.1k vibe).
    if (k < 100) return '${k.toStringAsFixed(1)}k';
    return '${k.round()}k';
  }
  final m = n / 1000000;
  return '${m.toStringAsFixed(1)}m';
}

String usageContextLabel(UsageStats usage) {
  if ((usage.contextMax ?? 0) > 0) {
    return '${compactTokenCount(usage.contextUsed ?? 0)}/${compactTokenCount(usage.contextMax!)}';
  }
  if (usage.total > 0) return '${compactTokenCount(usage.total)} tok';
  return '';
}
