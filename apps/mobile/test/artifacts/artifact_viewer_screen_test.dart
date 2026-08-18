import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';
import 'package:hermes_mobile/features/artifacts/artifact_viewer_screen.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Only the Markdown path is covered here — it needs no platform channel.
/// The HTML path drives a real `webview_flutter` platform view (WKWebView /
/// Android System WebView), which has no fake in this repo's test
/// dependencies and isn't exercised by `flutter_test`'s software renderer;
/// wiring one up would mean either adding a mock platform-view dependency
/// or hand-rolling a `TestWebViewPlatform`, both bigger than this task's
/// scope.
///
/// The *rules* that path enforces are not WebView-dependent, though: the
/// CSP wrapper, the navigation predicate and the renderer choice are pure
/// functions in `artifact_sandbox.dart` and are tested adversarially in
/// `artifact_sandbox_test.dart`. What remains unverified by automation is
/// only the wiring between them and the platform view (that
/// `setJavaScriptMode`/`loadHtmlString`/`onNavigationRequest` are actually
/// called with those values), plus the platform's own behaviour.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DashboardClient _clientWith(int statusCode, String body) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://gw.test',
      // Mirrors DashboardClient._ensureDio()'s BaseOptions so 4xx
      // responses reach readManagedFile as a normal Response.
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = _FixedAdapter(statusCode, body);
  return DashboardClient(
    profile: const ConnectionProfile(id: 'gw1', baseUrl: 'https://gw.test'),
    dio: dio,
  );
}

const _markdownArtifact = DetectedArtifact(
  path: '/tmp/report.md',
  name: 'report.md',
  kind: ArtifactFileKind.markdown,
  origin: ArtifactOrigin.toolResult,
);

Widget _wrap(DashboardClient? client, Widget child) {
  return ProviderScope(
    overrides: [dashboardClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  testWidgets('no gateway client shows the load-failed state without '
      'tripping a framework assert', (tester) async {
    // `_load` used to run synchronously from `initState`, and its
    // "no dashboard client" branch reads `context.l10n` — an inherited-widget
    // lookup before `initState` returns, which asserts in a debug build. It
    // is deferred past the first frame now.
    await tester.pumpWidget(
      _wrap(null, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Couldn't load this file."), findsOneWidget);
  });

  testWidgets('markdown artifact fetches through DashboardClient and renders '
      'via the MessageMarkdown pipeline', (tester) async {
    final dataUrl =
        'data:text/markdown;base64,${base64.encode(utf8.encode('# Hello artifact'))}';
    final client = _clientWith(
      200,
      jsonEncode({
        'name': 'report.md',
        'path': '/tmp/report.md',
        'size': 17,
        'mime_type': 'text/markdown',
        'data_url': dataUrl,
      }),
    );

    await tester.pumpWidget(
      _wrap(client, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(find.text('report.md'), findsOneWidget); // AppBar title
    expect(find.textContaining('Hello artifact'), findsOneWidget);
  });

  testWidgets('a remote image in a markdown artifact is never fetched', (
    tester,
  ) async {
    // End-to-end check of the sanitizer wiring: left raw, this would reach
    // `flutter_markdown_plus`'s default image builder and fire an
    // `Image.network` GET on first paint — a zero-click beacon confirming
    // the artifact was opened, from a device on the user's LAN.
    const body =
        '# Report\n\n![tracker](https://evil.example/p.png)\n\n'
        '![lan](http://192.168.1.1/x.png)\n';
    final client = _clientWith(
      200,
      jsonEncode({
        'name': 'report.md',
        'path': '/tmp/report.md',
        'size': body.length,
        'mime_type': 'text/markdown',
        'data_url':
            'data:text/markdown;base64,${base64.encode(utf8.encode(body))}',
      }),
    );

    await tester.pumpWidget(
      _wrap(client, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Report'), findsWidgets);
  });

  testWidgets('a 404 shows the not-found state with a retry action', (
    tester,
  ) async {
    final client = _clientWith(404, jsonEncode({'detail': 'File not found'}));

    await tester.pumpWidget(
      _wrap(client, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'File not found. It may have been moved or deleted on the gateway.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('a 403 shows the access-denied state', (tester) async {
    final client = _clientWith(
      403,
      jsonEncode({'detail': 'Access to sensitive files is not allowed'}),
    );

    await tester.pumpWidget(
      _wrap(client, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Access to this file is not allowed.'), findsOneWidget);
  });

  testWidgets('a 413 shows the too-large state', (tester) async {
    final client = _clientWith(
      413,
      jsonEncode({'detail': 'File is too large'}),
    );

    await tester.pumpWidget(
      _wrap(client, const ArtifactViewerScreen(artifact: _markdownArtifact)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This file is too large to preview here.'),
      findsOneWidget,
    );
  });
}
