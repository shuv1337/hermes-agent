/// Pure sandboxing logic for the artifact viewer — no widgets, no
/// platform channels, so every rule here is unit-testable without a real
/// WebView (see `test/artifacts/artifact_sandbox_test.dart`).
///
/// The threat model: an artifact's bytes are written by the agent, so they
/// are **untrusted**, and the phone rendering them sits on the user's
/// private network (it can reach the gateway, the router, and anything else
/// on the LAN). Nothing in an artifact may be able to reach the network, the
/// gateway session, or the device's storage on its own.
library;

import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';

/// What the viewer should do with a navigation the WebView asks for.
enum ArtifactNavigationAction {
  /// The bootstrap document `loadHtmlString` installs (`about:blank`).
  /// WKWebView *does* run this through `decidePolicyForNavigationAction`, so
  /// a delegate that blindly prevents everything renders a blank page on
  /// iOS. This is the only navigation the WebView is ever allowed to
  /// perform.
  allowInitialLoad,

  /// An http(s) target: refuse it inside the WebView, and offer the user a
  /// confirmed hand-off to the system browser via `url_launcher`.
  offerExternalOpen,

  /// Refuse silently. Everything that is not the two cases above lands
  /// here — `javascript:`, `data:`, `blob:`, `file:`, `content:`,
  /// `intent:`, `tel:`, `mailto:`, custom app schemes, scheme-relative and
  /// relative URLs, and unparseable junk.
  block,
}

/// The Content-Security-Policy the sandbox document carries.
///
///  - `default-src 'none'` — nothing loads unless explicitly allowed below.
///  - `img-src data:; font-src data:; media-src data:` — a self-contained
///    artifact's embedded assets render; nothing is fetched over the
///    network, so an artifact can never leak "this was opened" (or the
///    device's IP) through an image beacon.
///  - `style-src 'unsafe-inline'` — the document's own `<style>`/`style=`
///    renders. No remote host is ever in `style-src`, so CSS can't fetch
///    either.
///  - `script-src` — `'none'` unless the user has explicitly turned
///    JavaScript on for this one viewing. When JS is off this is a second,
///    independent gate behind `JavaScriptMode.disabled`; when it is on,
///    `'unsafe-inline'` permits the document's own inline script and
///    *nothing else* — no remote host, so a script can never pull down a
///    second-stage payload.
///  - `connect-src 'none'` — `fetch`/`XHR`/`WebSocket`/`sendBeacon` are
///    blocked outright, independent of the JS toggle.
///  - `frame-src 'none'; object-src 'none'` — no nested browsing contexts
///    (so no `<iframe srcdoc>` re-entry), no plugins.
///  - `form-action 'none'` — forms can't submit anywhere.
///  - `base-uri 'none'` — a `<base>` tag can't re-point relative URLs.
///
/// `sandbox` and `frame-ancestors` are deliberately absent: both are
/// ignored when a policy is delivered through a `<meta>` element, so
/// including them would be security theatre.
String artifactCsp({required bool allowScripts}) {
  final scriptSrc = allowScripts ? "'unsafe-inline'" : "'none'";
  return "default-src 'none'; "
      'img-src data:; font-src data:; media-src data:; '
      "style-src 'unsafe-inline'; script-src $scriptSrc; "
      "connect-src 'none'; frame-src 'none'; object-src 'none'; "
      "form-action 'none'; base-uri 'none';";
}

/// Wraps untrusted artifact HTML in a document whose `<head>` we control.
///
/// The raw bytes are **always** placed in the body of a fresh document
/// rather than patched into whatever `<head>`/`<html>` the artifact
/// supplies. Injecting into the document's own head is not safe: a hostile
/// author only has to make the first `<head`-looking thing in the file be a
/// `<header>` tag, an HTML comment (`<!-- <head> -->`), a `<script>` string
/// or an attribute value, and the CSP `<meta>` lands somewhere that is
/// either inside a comment, inside a script, or outside `<head>` — and a
/// CSP delivered by a `<meta>` outside `<head>` is *ignored by the parser*.
/// Wrapping has no such parse-order dependency: our `<meta>` is the first
/// thing in the document, full stop.
///
/// Nesting the artifact's own `<html>`/`<head>`/`<!DOCTYPE>` inside the body
/// is harmless — the HTML parser's "in body" insertion mode drops the
/// duplicate structural tags and keeps the content. In particular a CSP
/// `<meta>` the artifact supplies itself cannot loosen ours: it is parsed
/// into `<body>` (so it is ignored), and even if it were honoured, multiple
/// policies are enforced by intersection — an added policy can only ever
/// tighten.
String sandboxedArtifactHtml(String rawHtml, {required bool allowScripts}) {
  final csp = artifactCsp(allowScripts: allowScripts);
  return '<!DOCTYPE html><html><head>'
      '<meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$csp">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '</head><body>$rawHtml</body></html>';
}

/// Decides what to do with a navigation the sandboxed document asked for.
///
/// Deny-by-default: only the `about:blank` bootstrap is ever allowed to
/// proceed inside the WebView, and only http(s) is even *offered* to the
/// user as a system-browser hand-off. An unrecognised scheme is never
/// passed to `url_launcher` — handing an arbitrary `intent:`/custom scheme
/// to the platform launcher would let an artifact poke other apps.
///
/// [scriptsEnabled] closes the exfiltration channel that the hand-off
/// otherwise opens: a script can synthesise a navigation to
/// `https://attacker/?<data it scraped or prompted the user for>` at any
/// moment, without a tap. With scripts off, the only ways to reach this are
/// a user tapping a link that is literally written in the file, or a
/// `<meta refresh>` — in both cases the target is static text the user is
/// shown before anything opens. So when scripts are on, the document gets no
/// outbound path at all.
ArtifactNavigationAction decideArtifactNavigation(
  String url, {
  required bool scriptsEnabled,
}) {
  final trimmed = url.trim();
  // Some platform implementations report the bootstrap load with an empty
  // URL rather than `about:blank`.
  if (trimmed.isEmpty) return ArtifactNavigationAction.allowInitialLoad;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return ArtifactNavigationAction.block;

  switch (uri.scheme.toLowerCase()) {
    case 'about':
      // `about:blank` (with or without a fragment) only. `about:srcdoc` and
      // friends are refused.
      final path = uri.path.toLowerCase();
      return (path.isEmpty || path == 'blank')
          ? ArtifactNavigationAction.allowInitialLoad
          : ArtifactNavigationAction.block;
    case 'http':
    case 'https':
      if (uri.host.isEmpty) return ArtifactNavigationAction.block;
      return scriptsEnabled
          ? ArtifactNavigationAction.block
          : ArtifactNavigationAction.offerExternalOpen;
    default:
      return ArtifactNavigationAction.block;
  }
}

/// Which renderer an artifact opens in.
///
/// The **file extension decides**, always — the server-reported MIME type is
/// advisory and never promotes a `.md` file into the WebView. (It also never
/// demotes a `.html` one: the gateway derives the MIME from the same
/// filename the agent chose, so the two signals are not independent and
/// cross-checking them would buy nothing but a way to break legitimate
/// files.) The user tapped a chip labelled `report.md`; `report.md` must not
/// be able to render as HTML because a response header said so.
ArtifactFileKind rendererKindFor({
  required ArtifactFileKind detectedKind,
  String? serverMimeType,
}) => detectedKind;

/// MIME type to attach when sharing an artifact out of the app.
///
/// Derived from [kind] rather than echoing the server's `mime_type`, so a
/// hostile `mime_type` can't make the receiving app treat a `.md` file as
/// something executable.
String shareMimeTypeFor(ArtifactFileKind kind) => switch (kind) {
  ArtifactFileKind.markdown => 'text/markdown',
  ArtifactFileKind.html => 'text/html',
};

/// Strips anything path-like out of a server-supplied filename before it is
/// used to build a path in the temp directory for the share sheet.
String safeArtifactFileName(String name) {
  final last = name.replaceAll('\\', '/').split('/').last.trim();
  final cleaned = last.replaceAll(RegExp(r'[\x00-\x1f]'), '');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'artifact';
  return cleaned;
}

// `![alt](dest ...)` or `![alt][ref]` / `![ref]`. The destination is capped
// so a stray unclosed `](` can't swallow the rest of the document; a `data:`
// payload longer than that is left alone, which is the permitted case
// anyway.
final RegExp _markdownImageRe = RegExp(
  r'!\[([^\]]{0,512})\](\(([^)]{0,4096})\)|\[([^\]]{0,512})\])?',
);

// `[label]: destination "title"` link-reference definition.
final RegExp _markdownLinkDefRe = RegExp(
  r'^ {0,3}\[([^\]]{1,512})\]:\s*<?([^\s>]*)>?',
  multiLine: true,
);

final RegExp _markdownFenceRe = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Neutralises every image in a Markdown artifact whose source is not a
/// self-contained `data:` URI.
///
/// `flutter_markdown_plus` renders images through `kDefaultImageBuilder`,
/// which hands http(s) sources to `Image.network` and *everything else*
/// (including `file:` and bare relative paths) to `Image.file`. Left alone,
/// `![](https://attacker.example/p.png)` in an agent-written `.md` file is a
/// zero-click beacon: it fires the moment the artifact is opened, confirming
/// the file was read and leaking the device's public IP, and it can be
/// pointed at a LAN address (`http://192.168.1.1/...`) to make the phone
/// issue a GET against the user's own network. The HTML path blocks exactly
/// this with `img-src data:`; this brings the Markdown path to the same
/// rule.
///
/// A blocked image is replaced with its own source text inside a code span,
/// so the reader can see what was there (and export the raw file) without
/// anything being fetched. Fenced code blocks are left untouched — images
/// inside them never render in the first place.
String sanitizeMarkdownArtifact(String markdown) {
  if (!markdown.contains('![')) return markdown;

  final definitions = <String, String>{};
  for (final match in _markdownLinkDefRe.allMatches(markdown)) {
    final label = match.group(1)!.trim().toLowerCase();
    definitions.putIfAbsent(label, () => match.group(2)?.trim() ?? '');
  }

  bool isInlineData(String destination) {
    var dest = destination.trim();
    if (dest.startsWith('<')) {
      // `<dest>` form: the destination ends at the first `>`.
      final close = dest.indexOf('>');
      dest = close >= 0 ? dest.substring(1, close) : dest.substring(1);
    } else {
      // Bare form: the destination ends at the first whitespace, anything
      // after it is a `"title"`.
      dest = dest.split(RegExp(r'\s')).first;
    }
    return dest.trim().toLowerCase().startsWith('data:');
  }

  String neutralize(String original) {
    // Backticks/newlines in the source would break out of the code span.
    final flattened = original
        .replaceAll('`', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '`$flattened`';
  }

  String transform(String segment) {
    return segment.replaceAllMapped(_markdownImageRe, (match) {
      final inlineDestination = match.group(3);
      if (inlineDestination != null) {
        return isInlineData(inlineDestination)
            ? match.group(0)!
            : neutralize(match.group(0)!);
      }
      // Reference (`![alt][label]`) or shortcut (`![label]`) form.
      final label = (match.group(4)?.trim().isNotEmpty ?? false)
          ? match.group(4)!.trim()
          : match.group(1)!.trim();
      final resolved = definitions[label.toLowerCase()];
      if (resolved != null && isInlineData(resolved)) return match.group(0)!;
      return neutralize(match.group(0)!);
    });
  }

  // Walk the document a line at a time so fenced code can be skipped, but
  // transform whole runs at once — an image's destination may legally span a
  // newline, and a line-by-line regex would miss that.
  final result = <String>[];
  final pending = <String>[];
  var inFence = false;
  String? fenceMarker;

  void flushPending() {
    if (pending.isEmpty) return;
    result.addAll(transform(pending.join('\n')).split('\n'));
    pending.clear();
  }

  for (final line in markdown.split('\n')) {
    final fence = _markdownFenceRe.firstMatch(line)?.group(1);
    if (inFence) {
      result.add(line);
      if (fence != null && fence[0] == fenceMarker) {
        inFence = false;
        fenceMarker = null;
      }
      continue;
    }
    if (fence != null) {
      flushPending();
      result.add(line);
      inFence = true;
      fenceMarker = fence[0];
      continue;
    }
    pending.add(line);
  }
  flushPending();
  return result.join('\n');
}
