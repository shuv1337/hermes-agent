import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';

/// File-artifact detection for the session transcript — recognizes
/// `.md`/`.markdown`/`.html`/`.htm` files the agent produced during a turn so
/// the chat UI can offer a tappable chip to open them (see
/// `ArtifactViewerScreen`).
///
/// This mirrors, and deliberately narrows, Desktop's
/// `apps/desktop/src/app/artifacts/artifact-utils.ts`. Desktop scans
/// free-form assistant/tool text for *any* path- or URL-shaped string
/// (`PATH_RE`, `KEY_HINT_RE` matching keys like `path`/`file`/`url`/
/// `output`/`result`) across images, files, and links, and shows the whole
/// index in a dedicated Artifacts page. On a phone, inline in the transcript,
/// a false positive is worse than a miss — a chip that 404s on tap reads as
/// the app being broken, not "best effort" — so this module narrows Desktop's
/// heuristics in four ways:
///
///  1. **Scope**: only `.md`/`.markdown`/`.html`/`.htm` are considered.
///     Desktop's `link`/`image` kinds (bare URLs, pictures) are out of scope
///     here entirely — mobile only renders local gateway files.
///  2. **Tool-result detection is allow-listed by tool name** (`write_file`,
///     `patch` — see `tools/file_tools.py`), and only looks at the exact
///     structured fields those tools actually return
///     (`resolved_path`/`path`/`files_modified`/`files_created`, per
///     `tools/file_operations.py`'s `WriteResult`/`PatchResult.to_dict()`) —
///     not "any string under a path/file/url-ish JSON key" the way Desktop's
///     `KEY_HINT_RE` does against arbitrary tool payloads. A failed write
///     (a truthy `error` field) never surfaces a chip.
///  3. **Assistant-text detection requires an explicit "this names a file"
///     signal** — a backtick code span (`` `report.md` ``) or an `@file:`
///     workspace ref (`tui_gateway/methods_prompt.py`'s `ref_text` format) —
///     rather than Desktop's raw `PATH_RE` scan of unquoted prose. "the
///     report.md file" in running text does not produce a chip;
///     `` `report.md` `` does. This is the case explicitly called out in the
///     brief: mentioning a filename is not the same as producing one.
///  4. **No JSON-payload deep walk** of arbitrary message content the way
///     Desktop's `collectStringValues` does — only the tool message's own
///     top-level result fields are inspected.
///
/// Everything here is a pure function over [HermesMessage] — no network, no
/// widgets — so it can be unit tested directly.
enum ArtifactFileKind { markdown, html }

/// Where a [DetectedArtifact] was recognized from — informational only
/// (surfaced in tests / debug output), not used to change viewer behavior.
enum ArtifactOrigin { toolResult, textMention, fileRef }

@immutable
class DetectedArtifact {
  const DetectedArtifact({
    required this.path,
    required this.name,
    required this.kind,
    required this.origin,
  });

  /// Value to pass as `?path=` to `GET /api/files/read` — either an absolute
  /// gateway-side path (typical for `write_file`/`patch` results) or a
  /// workspace-relative `@file:` ref value; the gateway resolves either.
  final String path;

  /// Display name — the final path segment.
  final String name;

  final ArtifactFileKind kind;
  final ArtifactOrigin origin;

  @override
  bool operator ==(Object other) =>
      other is DetectedArtifact && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);

  @override
  String toString() =>
      'DetectedArtifact(path: $path, kind: $kind, origin: $origin)';
}

/// Tools whose result JSON can report a file this app should treat as
/// agent-produced (`tools/file_tools.py`). Deliberately narrow — see class
/// doc point 2. `read_file`/search tools are excluded on purpose: reading or
/// finding a file is not the same signal as the agent having written it.
const _fileWriteToolNames = {'write_file', 'patch'};

final RegExp _artifactExtensionRe = RegExp(
  r'\.(md|markdown|html?|htm)$',
  caseSensitive: false,
);

final RegExp _backtickSpanRe = RegExp(r'`([^`\n]+)`');

// `@file:<value>` where <value> is backtick/double/single-quoted (used when
// the path has spaces or bracket-ish characters — mirrors the gateway's
// `_format_ref_value` / desktop `formatRefValue` quoting) or otherwise a
// single non-whitespace token.
final RegExp _fileRefRe = RegExp(
  r'@file:(`[^`]+`|"[^"]+"|'
  r"'[^']+'"
  r'|\S+)',
);

ArtifactFileKind? _kindForPath(String path) {
  final match = _artifactExtensionRe.firstMatch(path);
  if (match == null) return null;
  final ext = match.group(1)!.toLowerCase();
  return (ext == 'md' || ext == 'markdown')
      ? ArtifactFileKind.markdown
      : ArtifactFileKind.html;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

/// Strips a single layer of matching backtick/double/single quotes, if
/// present — the inverse of the gateway's `_format_ref_value` quoting.
String _unquote(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    final matchingQuote =
        (first == '`' && last == '`') ||
        (first == '"' && last == '"') ||
        (first == "'" && last == "'");
    if (matchingQuote) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

List<DetectedArtifact> _fromToolResult(HermesMessage message) {
  final toolName = message.toolName?.trim();
  if (toolName == null || !_fileWriteToolNames.contains(toolName)) {
    return const [];
  }
  final content = message.content;
  if (content == null || content.trim().isEmpty) return const [];

  dynamic decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];

  // A failed write never produced a file worth opening.
  final error = decoded['error'];
  if (error != null && '$error'.trim().isNotEmpty) return const [];

  final candidates = <String>[];
  void addString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      candidates.add(value.trim());
    }
  }

  void addList(dynamic value) {
    if (value is List) {
      for (final item in value) {
        addString(item);
      }
    }
  }

  addString(decoded['resolved_path']);
  addString(decoded['path']);
  addList(decoded['files_modified']);
  addList(decoded['files_created']);

  final seen = <String>{};
  final out = <DetectedArtifact>[];
  for (final path in candidates) {
    final kind = _kindForPath(path);
    if (kind == null) continue;
    if (!seen.add(path)) continue;
    out.add(
      DetectedArtifact(
        path: path,
        name: _basename(path),
        kind: kind,
        origin: ArtifactOrigin.toolResult,
      ),
    );
  }
  return out;
}

List<DetectedArtifact> _fromAssistantText(HermesMessage message) {
  final text = message.content;
  if (text == null || text.trim().isEmpty) return const [];

  final seen = <String>{};
  final out = <DetectedArtifact>[];

  void consider(String raw, ArtifactOrigin origin) {
    final path = _unquote(raw.trim());
    if (path.isEmpty) return;
    // Links are handled by chat markdown / Desktop's `link` kind, not here.
    if (path.startsWith('http://') || path.startsWith('https://')) return;
    final kind = _kindForPath(path);
    if (kind == null) return;
    if (!seen.add(path)) return;
    out.add(
      DetectedArtifact(
        path: path,
        name: _basename(path),
        kind: kind,
        origin: origin,
      ),
    );
  }

  for (final match in _backtickSpanRe.allMatches(text)) {
    consider(match.group(1) ?? '', ArtifactOrigin.textMention);
  }
  for (final match in _fileRefRe.allMatches(text)) {
    consider(match.group(1) ?? '', ArtifactOrigin.fileRef);
  }

  return out;
}

/// Detects artifacts carried by a single transcript message. Tool-result
/// messages (`role: tool`/`function`) are checked against the structured
/// write/patch result shape; assistant messages are checked for backtick
/// spans and `@file:` refs. All other roles (user, system) never produce a
/// chip.
List<DetectedArtifact> detectArtifactsInMessage(HermesMessage message) {
  if (message.isTool) return _fromToolResult(message);
  if (message.isAssistant) return _fromAssistantText(message);
  return const [];
}
