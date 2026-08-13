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
///  4. **A backticked prose mention must correlate to a path the session is
///     known to have written.** A bare `` `summary.md` `` in prose carries no
///     directory, so sending it as `?path=summary.md` asks the gateway to
///     resolve it against the managed-workspace *root* — which 404s whenever
///     the agent actually wrote `reports/summary.md`. The transcript almost
///     always already contains the `write_file`/`patch` result that produced
///     the file, complete with its resolved path, so prose mentions are
///     resolved against that set ([SessionArtifactPaths]) and the chip carries
///     the **resolved** path. A mention that resolves to nothing known raises
///     no chip at all — silently, because a chip that 404s on tap reads as a
///     broken app while a missing chip merely reads as a plain message.
///     `@file:` refs are exempt: the gateway mints them workspace-relative
///     (`server.py`'s `_attachment_ref_path`, absolute when outside the
///     workspace), so they are already complete and are chipped as written.
///  5. **No JSON-payload deep walk** of arbitrary message content the way
///     Desktop's `collectStringValues` does — only the tool message's own
///     top-level result fields are inspected.
///
/// Everything here is a pure function over [HermesMessage] (plus, for prose,
/// the session's [SessionArtifactPaths]) — no network, no widgets — so it can
/// be unit tested directly.
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

/// Normalizes a path for *matching* only — never for sending. Windows-style
/// separators become `/` and a leading `./` is dropped, so `./notes/a.md`,
/// `notes\a.md` and `notes/a.md` all compare equal.
String _normalizeForMatch(String path) {
  var p = path.trim().replaceAll('\\', '/');
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  return p;
}

/// The artifact paths a session is *known* to have produced, harvested from
/// its `write_file`/`patch` tool results — the fully-resolved, gateway-side
/// paths those tools report.
///
/// This is what turns a directory-less prose mention (`` `summary.md` ``)
/// into something openable: [resolve] maps the mention onto the real path the
/// agent wrote, or returns null so the caller can decline to draw a chip.
///
/// Build it **once per transcript change** and pass it down to per-message
/// detection — building it inside a message widget would rescan the whole
/// transcript on every rebuild, and chat messages rebuild on every streamed
/// token. Pass the previous instance as [previous] and unchanged tool results
/// are reused verbatim instead of being JSON-decoded again.
@immutable
class SessionArtifactPaths {
  const SessionArtifactPaths._(
    this._byNormalized,
    this._byBasename,
    this._memo,
  );

  /// Nothing known — the safe default. With an empty index, backticked prose
  /// mentions resolve to nothing and therefore raise no chips; tool results
  /// and `@file:` refs are unaffected.
  static const empty = SessionArtifactPaths._({}, {}, {});

  /// Normalized path -> the path exactly as the tool reported it (the form
  /// that gets sent to `GET /api/files/read`).
  final Map<String, String> _byNormalized;

  /// Lower-cased basename -> every distinct known path carrying it. More than
  /// one entry means a bare mention of that basename is ambiguous.
  final Map<String, List<String>> _byBasename;

  /// Message id -> (content it was derived from, artifact paths it named).
  /// Purely a decode cache for incremental rebuilds; never read as truth.
  final Map<String, _WrittenPaths> _memo;

  factory SessionArtifactPaths.fromMessages(
    Iterable<HermesMessage> messages, {
    SessionArtifactPaths previous = SessionArtifactPaths.empty,
  }) {
    final memo = <String, _WrittenPaths>{};
    final byNormalized = <String, String>{};
    final byBasename = <String, List<String>>{};

    for (final message in messages) {
      if (!message.isTool) continue;
      final toolName = message.toolName?.trim();
      if (toolName == null || !_fileWriteToolNames.contains(toolName)) continue;

      final content = message.content;
      final cached = previous._memo[message.id];
      final written =
          (cached != null &&
              (identical(cached.content, content) || cached.content == content))
          ? cached.paths
          : _writtenArtifactPaths(message);
      memo[message.id] = _WrittenPaths(content, written);

      for (final path in written) {
        final normalized = _normalizeForMatch(path);
        if (byNormalized.containsKey(normalized)) continue;
        byNormalized[normalized] = path;
        byBasename
            .putIfAbsent(_basename(path).toLowerCase(), () => <String>[])
            .add(path);
      }
    }

    return SessionArtifactPaths._(byNormalized, byBasename, memo);
  }

  /// Every known written artifact path, in the form the gateway reported it.
  Iterable<String> get paths => _byNormalized.values;

  bool get isEmpty => _byNormalized.isEmpty;

  /// Maps a prose mention onto a known written path, or null when it cannot
  /// be placed. Tried in order, most-specific first:
  ///
  ///  1. the mention *is* a known path (an absolute path echoed in prose);
  ///  2. exactly one known path ends with the mention on a segment boundary
  ///     (`reports/summary.md` naming `/ws/out/reports/summary.md`);
  ///  3. exactly one known path shares its basename (the bare `summary.md`
  ///     case this whole index exists for).
  ///
  /// Ambiguity — two different known paths matching equally well — resolves
  /// to null: guessing between them would draw a chip that opens the wrong
  /// file, which is worse than drawing none.
  String? resolve(String mention) {
    if (_byNormalized.isEmpty) return null;
    final normalized = _normalizeForMatch(mention);
    if (normalized.isEmpty) return null;

    final exact = _byNormalized[normalized];
    if (exact != null) return exact;

    if (normalized.contains('/')) {
      final suffix = '/$normalized';
      String? hit;
      for (final entry in _byNormalized.entries) {
        if (!entry.key.endsWith(suffix)) continue;
        if (hit != null && hit != entry.value) return null;
        hit = entry.value;
      }
      if (hit != null) return hit;
    }

    final sameName = _byBasename[_basename(normalized).toLowerCase()];
    if (sameName == null || sameName.length != 1) return null;
    return sameName.single;
  }
}

@immutable
class _WrittenPaths {
  const _WrittenPaths(this.content, this.paths);
  final String? content;
  final List<String> paths;
}

/// The artifact-extension paths a `write_file`/`patch` result names, in the
/// exact form the tool reported them. Callers must have already checked the
/// tool name against [_fileWriteToolNames].
List<String> _writtenArtifactPaths(HermesMessage message) {
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

  final out = <String>[];
  for (final path in candidates) {
    if (_kindForPath(path) == null) continue;
    if (out.contains(path)) continue;
    out.add(path);
  }
  return out;
}

List<DetectedArtifact> _fromToolResult(HermesMessage message) {
  final toolName = message.toolName?.trim();
  if (toolName == null || !_fileWriteToolNames.contains(toolName)) {
    return const [];
  }
  return [
    for (final path in _writtenArtifactPaths(message))
      DetectedArtifact(
        path: path,
        name: _basename(path),
        kind: _kindForPath(path)!,
        origin: ArtifactOrigin.toolResult,
      ),
  ];
}

List<DetectedArtifact> _fromAssistantText(
  HermesMessage message,
  SessionArtifactPaths known,
) {
  final text = message.content;
  if (text == null || text.trim().isEmpty) return const [];

  final seen = <String>{};
  final out = <DetectedArtifact>[];

  void emit(String path, ArtifactOrigin origin) {
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

  /// A mention only becomes a chip if the session actually wrote a matching
  /// file — see class doc point 4.
  String? candidate(String raw) {
    final path = _unquote(raw.trim());
    if (path.isEmpty) return null;
    // Links are handled by chat markdown / Desktop's `link` kind, not here.
    if (path.startsWith('http://') || path.startsWith('https://')) return null;
    if (_kindForPath(path) == null) return null;
    return path;
  }

  for (final match in _backtickSpanRe.allMatches(text)) {
    final mention = candidate(match.group(1) ?? '');
    if (mention == null) continue;
    final resolved = known.resolve(mention);
    if (resolved == null) continue;
    emit(resolved, ArtifactOrigin.textMention);
  }
  // `@file:` values arrive workspace-relative (or absolute) straight from the
  // gateway (`_attachment_ref_path`), so they are complete on their own: they
  // are chipped as written, with no correlation step to second-guess them.
  for (final match in _fileRefRe.allMatches(text)) {
    final mention = candidate(match.group(1) ?? '');
    if (mention == null) continue;
    emit(mention, ArtifactOrigin.fileRef);
  }

  return out;
}

/// Detects artifacts carried by a single transcript message. Tool-result
/// messages (`role: tool`/`function`) are checked against the structured
/// write/patch result shape; assistant messages are checked for backtick
/// spans and `@file:` refs. All other roles (user, system) never produce a
/// chip.
///
/// [known] is the session's [SessionArtifactPaths] — build it once per
/// transcript change with [SessionArtifactPaths.fromMessages] and pass the
/// same instance to every message. Backticked prose mentions are chipped only
/// when they resolve against it; with the default empty index they never are,
/// which is the safe behavior for a caller that has no session context.
List<DetectedArtifact> detectArtifactsInMessage(
  HermesMessage message, {
  SessionArtifactPaths known = SessionArtifactPaths.empty,
}) {
  if (message.isTool) return _fromToolResult(message);
  if (message.isAssistant) return _fromAssistantText(message, known);
  return const [];
}
