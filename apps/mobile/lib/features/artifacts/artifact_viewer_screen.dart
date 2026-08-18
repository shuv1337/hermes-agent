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
import 'package:hermes_mobile/features/artifacts/artifact_sandbox.dart';
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
/// own. The rules themselves live in `artifact_sandbox.dart` as pure
/// functions so they can be unit tested without a platform WebView; this
/// widget only wires them up:
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
///  - [sandboxedArtifactHtml] wraps the bytes in a document whose `<head>`
///    we own, carrying a restrictive CSP `<meta>`; `script-src` is `'none'`
///    unless the user turned JS on for this viewing.
///  - [decideArtifactNavigation] gates every navigation: only the
///    `about:blank` bootstrap proceeds, http(s) is offered as a confirmed
///    system-browser hand-off (and only while scripts are off), and every
///    other scheme is refused without being handed to `url_launcher`.
///  - JS dialogs (`alert`/`confirm`/`prompt`) are swallowed rather than
///    shown: a native-looking dialog rendered by an untrusted document is a
///    phishing surface, and `prompt()` is a credential-harvesting one.
///  - Camera/microphone permission requests are denied outright.
///  - [WebViewCookieManager.clearCookies] runs before every load. There is
///    **no** way to force a fully non-persistent (incognito-style)
///    `WKWebsiteDataStore`/`WebStorage` through the current
///    `webview_flutter`/`webview_flutter_wkwebview` 3.26 public API — so if
///    the user enables JavaScript and the document uses `localStorage`/
///    IndexedDB, that can still land in the platform WebView's default,
///    persistent data store. This is a known, documented residual risk (see
///    the task report), not a silent gap.
///
/// The Markdown path is sandboxed too: [sanitizeMarkdownArtifact] blocks
/// non-`data:` images, which `flutter_markdown_plus` would otherwise fetch
/// with `Image.network` the moment the artifact opens.
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

  /// Single-flight guard for the external-link confirmation, so a document
  /// that fires navigations in a loop can't stack dialogs on the user.
  bool _promptingExternalOpen = false;

  /// The renderer is chosen by the filename, never by the server's MIME
  /// type — see [rendererKindFor].
  ArtifactFileKind get _rendererKind =>
      rendererKindFor(detectedKind: widget.artifact.kind);

  @override
  void initState() {
    super.initState();
    // Deferred a frame on purpose. `_load` runs synchronously up to its first
    // `await`, and its `dashboardClientProvider == null` branch reads
    // `context.l10n` on that synchronous stretch — an inherited-widget lookup
    // before `initState` has returned, which trips
    // `dependOnInheritedWidgetOfExactType` in a debug build. `_state` already
    // starts at `loading`, so nothing flickers by waiting one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_load());
    });
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
      if (_rendererKind == ArtifactFileKind.html) {
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
      // cookie to in the first place (see [artifactCsp]).
    }

    final scriptsEnabled = _jsEnabled;
    final controller =
        WebViewController(
            // An untrusted document must never be able to reach the camera
            // or microphone. `about:blank` counts as a secure context, so
            // `getUserMedia` is reachable once scripts are on; the platform
            // default on iOS is to *prompt*, which is not good enough here.
            onPermissionRequest: (request) => request.deny(),
          )
          ..setJavaScriptMode(
            scriptsEnabled
                ? JavaScriptMode.unrestricted
                : JavaScriptMode.disabled,
          )
          ..setBackgroundColor(Colors.transparent)
          // Swallow JS dialogs instead of letting the platform render them:
          // an untrusted document showing a native alert (or a `prompt()`
          // asking for a password) is a phishing surface, and there is no
          // legitimate use for one in a static artifact.
          ..setOnJavaScriptAlertDialog((request) async {})
          ..setOnJavaScriptConfirmDialog((request) async => false)
          ..setOnJavaScriptTextInputDialog((request) async => '')
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                switch (decideArtifactNavigation(
                  request.url,
                  scriptsEnabled: scriptsEnabled,
                )) {
                  case ArtifactNavigationAction.allowInitialLoad:
                    // Only ever the `about:blank` document `loadHtmlString`
                    // installs. WKWebView routes that through this delegate,
                    // so preventing it would render a blank page on iOS.
                    return NavigationDecision.navigate;
                  case ArtifactNavigationAction.offerExternalOpen:
                    final uri = Uri.tryParse(request.url);
                    if (uri != null) unawaited(_confirmOpenExternally(uri));
                    return NavigationDecision.prevent;
                  case ArtifactNavigationAction.block:
                    return NavigationDecision.prevent;
                }
              },
            ),
          )
          ..loadHtmlString(
            sandboxedArtifactHtml(html, allowScripts: scriptsEnabled),
          );

    if (!mounted) return;
    setState(() => _webController = controller);
  }

  Future<void> _confirmOpenExternally(Uri uri) async {
    if (!mounted || _promptingExternalOpen) return;
    _promptingExternalOpen = true;
    try {
      final open = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.artifactOpenLinkTitle),
          content: Text(
            dialogContext.l10n.artifactOpenLinkBody(uri.toString()),
          ),
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
    } finally {
      _promptingExternalOpen = false;
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
      // `name` and `mime_type` both come from the gateway response for an
      // agent-chosen filename — neither is allowed to steer where we write
      // or how the receiving app interprets the file.
      final safeName = safeArtifactFileName(content.name);
      final file = File('${dir.path}/$safeName');
      await file.writeAsString(text);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: shareMimeTypeFor(_rendererKind))],
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
        if (_rendererKind == ArtifactFileKind.markdown) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            // Sanitized, not raw: an unsanitized remote image URL would be
            // fetched by `flutter_markdown_plus` on first paint.
            child: MessageMarkdown(data: sanitizeMarkdownArtifact(text)),
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
