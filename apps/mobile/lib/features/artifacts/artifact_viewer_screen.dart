import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';
import 'package:hermes_mobile/features/sessions/message_markdown.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

enum _LoadState { loading, loaded, notFound, forbidden, tooLarge, error }

/// Full-screen viewer for a `.md`/`.html` artifact the agent produced during
/// a turn — the mobile analogue of Hermes Desktop's artifacts pane.
///
/// Markdown renders through the same [MessageMarkdown] pipeline used for
/// chat bubbles, so artifacts look like the rest of the app rather than a
/// separate reader. HTML renders in a sandboxed [WebViewController].
///
/// ## HTML security model
///
/// Agent-generated HTML is untrusted content on a phone that can reach the
/// user's private network, so the WebView never talks to the network on its
/// own:
///
///  - Bytes are fetched here in Dart through the authenticated
///    [DashboardClient] (`GET /api/files/read`) and handed to
///    `loadHtmlString`. The WebView is never pointed at a gateway URL —
///    session cookies never enter it (nothing is ever attached to it in the
///    first place; see [_initWebView]).
///  - JavaScript is **off by default** ([JavaScriptMode.disabled]) every
///    time this screen opens. [_jsEnabled] is local `State` — it is never
///    persisted, so re-opening the same artifact (or any other) starts from
///    off again.
///  - [_sandboxedHtml] injects a restrictive CSP `<meta>` ahead of the
///    document's own `<head>` content — see that method for exactly what it
///    allows and why.
///  - [NavigationDelegate.onNavigationRequest] denies every navigation that
///    isn't the initial `loadHtmlString` load (that call does not itself
///    raise a navigation request in either platform's implementation — only
///    link taps / `window.location` / form submissions do). An http(s)
///    target is offered to the user as an system-browser handoff via
///    [url_launcher]; anything else (including `file://`) is silently
///    blocked. This also means the WebView can never navigate itself to a
///    `file://` URL.
///  - [WebViewCookieManager.clearCookies] runs before every load. There is
///    **no** way to force a fully non-persistent (incognito-style)
///    `WKWebsiteDataStore`/`WebStorage` through the current
///    `webview_flutter`/`webview_flutter_wkwebview` 3.26 public API — so if
///    the user enables JavaScript and the document uses `localStorage`/
///    IndexedDB, that can still land in the platform WebView's default,
///    persistent data store. This is a known, documented residual risk (see
///    the task report), not a silent gap.
class ArtifactViewerScreen extends ConsumerStatefulWidget {
  const ArtifactViewerScreen({super.key, required this.artifact});

  final DetectedArtifact artifact;

  @override
  ConsumerState<ArtifactViewerScreen> createState() =>
      _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends ConsumerState<ArtifactViewerScreen> {
  _LoadState _state = _LoadState.loading;
  String? _errorDetail;
  ManagedFileContent? _content;
  String? _text;

  WebViewController? _webController;

  /// Local to this screen instance — deliberately not persisted anywhere, so
  /// every fresh open (including re-opening the same file) starts at off.
  bool _jsEnabled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _errorDetail = null;
    });

    final dashboard = ref.read(dashboardClientProvider);
    if (dashboard == null) {
      setState(() {
        _state = _LoadState.error;
        _errorDetail = context.l10n.artifactLoadFailed;
      });
      return;
    }

    try {
      final content = await dashboard.readManagedFile(widget.artifact.path);
      final text = content.decodeText();
      if (!mounted) return;
      setState(() {
        _content = content;
        _text = text;
        _state = _LoadState.loaded;
      });
      if (widget.artifact.kind == ArtifactFileKind.html) {
        await _initWebView(text);
      }
    } on ManagedFileException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = switch (e.kind) {
          ManagedFileErrorKind.notFound => _LoadState.notFound,
          ManagedFileErrorKind.forbidden => _LoadState.forbidden,
          ManagedFileErrorKind.tooLarge => _LoadState.tooLarge,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorDetail = '$e';
      });
    }
  }

  Future<void> _initWebView(String html) async {
    // Best-effort: strips cookies from whatever data store the platform
    // WebView uses before every load. See the class doc for why this isn't
    // a full guarantee of "no persistent storage".
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // Not fatal — the document still never gets a network path to send a
      // cookie to in the first place (see the CSP in `_sandboxedHtml`).
    }

    final controller = WebViewController()
      ..setJavaScriptMode(
        _jsEnabled ? JavaScriptMode.unrestricted : JavaScriptMode.disabled,
      )
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final isHttp =
                uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
            if (isHttp) {
              unawaited(_confirmOpenExternally(uri));
            }
            // Always prevent — the WebView itself never follows a link, a
            // redirect, or a `file://`/`javascript:`/custom-scheme target.
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_sandboxedHtml(html));

    if (!mounted) return;
    setState(() => _webController = controller);
  }

  /// Injects a restrictive Content-Security-Policy `<meta>` ahead of
  /// whatever `<head>` (or `<html>`) the document supplies, so it applies
  /// before any of the document's own tags are parsed. The policy:
  ///
  ///  - `default-src 'none'` — nothing loads unless explicitly allowed below.
  ///  - `img-src data:; font-src data:; media-src data:` — inline `data:`
  ///    assets (a self-contained artifact's embedded images/fonts) render;
  ///    nothing is fetched over the network.
  ///  - `style-src 'unsafe-inline'` — the document's own `<style>`/`style=`
  ///    renders.
  ///  - `script-src 'unsafe-inline'` — inline `<script>` is *permitted by
  ///    the policy* only so the JS toggle has something to turn on;
  ///    `setJavaScriptMode(disabled)` is the actual gate while the toggle is
  ///    off. Either way, no remote host is ever in `script-src`, so a script
  ///    can't load a remote payload even after the toggle is flipped on.
  ///  - `connect-src 'none'` — `fetch`/`XHR`/`WebSocket` beaconing is
  ///    blocked outright, independent of the JS toggle.
  ///  - `frame-src 'none'; object-src 'none'` — no nested browsing contexts,
  ///    no plugins.
  ///  - `form-action 'none'` — forms can't submit anywhere.
  ///  - `base-uri 'none'` — a `<base>` tag can't redirect relative URLs.
  String _sandboxedHtml(String rawHtml) {
    const csp =
        "default-src 'none'; "
        "img-src data:; font-src data:; media-src data:; "
        "style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
        "connect-src 'none'; frame-src 'none'; object-src 'none'; "
        "form-action 'none'; base-uri 'none';";
    const meta = '<meta http-equiv="Content-Security-Policy" content="$csp">';

    final lower = rawHtml.toLowerCase();
    final headIdx = lower.indexOf('<head');
    if (headIdx >= 0) {
      final headEnd = rawHtml.indexOf('>', headIdx);
      if (headEnd >= 0) {
        return rawHtml.replaceRange(headEnd + 1, headEnd + 1, meta);
      }
    }
    final htmlIdx = lower.indexOf('<html');
    if (htmlIdx >= 0) {
      final htmlEnd = rawHtml.indexOf('>', htmlIdx);
      if (htmlEnd >= 0) {
        return rawHtml.replaceRange(
          htmlEnd + 1,
          htmlEnd + 1,
          '<head>$meta</head>',
        );
      }
    }
    return '<html><head>$meta</head><body>$rawHtml</body></html>';
  }

  Future<void> _confirmOpenExternally(Uri uri) async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.artifactOpenLinkTitle),
        content: Text(dialogContext.l10n.artifactOpenLinkBody(uri.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.artifactOpenLinkAction),
          ),
        ],
      ),
    );
    if (open == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setJsEnabled(bool value) async {
    setState(() => _jsEnabled = value);
    final text = _text;
    // Rebuilding the controller from scratch (rather than flipping the mode
    // on the live one) means a page that already ran unrestricted script
    // doesn't keep any in-page state across the toggle — the reload is the
    // reset.
    if (text != null) {
      await _initWebView(text);
    }
  }

  Future<void> _share() async {
    final content = _content;
    final text = _text;
    if (content == null || text == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final safeName = content.name.isEmpty ? 'artifact' : content.name;
      final file = File('${dir.path}/$safeName');
      await file.writeAsString(text);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: content.mimeType)],
          subject: safeName,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.exportFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.artifact.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.artifactReload,
            onPressed: _state == _LoadState.loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.l10n.export,
            onPressed: _state == _LoadState.loaded ? _share : null,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.notFound:
        return _ArtifactErrorView(
          icon: Icons.search_off,
          message: context.l10n.artifactNotFound,
          onRetry: _load,
        );
      case _LoadState.forbidden:
        return _ArtifactErrorView(
          icon: Icons.lock_outline,
          message: context.l10n.artifactAccessDenied,
          onRetry: _load,
        );
      case _LoadState.tooLarge:
        return _ArtifactErrorView(
          icon: Icons.sd_card_alert_outlined,
          message: context.l10n.artifactTooLarge,
          onRetry: _load,
        );
      case _LoadState.error:
        return _ArtifactErrorView(
          icon: Icons.error_outline,
          message: _errorDetail ?? context.l10n.artifactLoadFailed,
          onRetry: _load,
        );
      case _LoadState.loaded:
        final text = _text ?? '';
        if (widget.artifact.kind == ArtifactFileKind.markdown) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MessageMarkdown(data: text),
          );
        }

        final controller = _webController;
        return Column(
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: SwitchListTile(
                dense: true,
                title: Text(context.l10n.artifactEnableJs),
                subtitle: Text(
                  context.l10n.artifactEnableJsWarning,
                  style: theme.textTheme.bodySmall,
                ),
                value: _jsEnabled,
                onChanged: (value) => unawaited(_setJsEnabled(value)),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: controller == null
                  ? const Center(child: CircularProgressIndicator())
                  : WebViewWidget(controller: controller),
            ),
          ],
        );
    }
  }
}

class _ArtifactErrorView extends StatelessWidget {
  const _ArtifactErrorView({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}
