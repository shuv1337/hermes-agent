// The demo workspace's artifacts, end to end.
//
// The in-app artifact viewer is paused for v1 (see `kArtifactViewerEnabled`
// in `lib/features/artifacts/artifact_viewer_flags.dart`), so the session
// this suite exercises is no longer part of `DemoFixtures.buildSessions` —
// see `DemoFixtures.latencyReviewSessionForTests`, which builds the exact
// same seed data directly so this suite still holds the feature's two halves
// green, ready for re-enabling:
//
//  1. The seeded transcript must produce artifact chips — checked against the
//     *real* `detectArtifactsInMessage`, imported here rather than
//     reimplemented, so a change to the detection rules fails this test
//     instead of silently emptying the demo workspace of artifacts.
//  2. Tapping such a chip must actually fetch bytes — checked by booting a
//     real `DemoGatewayServer` on loopback and reading through the app's own
//     `DashboardClient.readManagedFile`, the exact call the viewer makes.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/demo/demo_fixtures.dart';
import 'package:hermes_mobile/core/demo/demo_gateway_server.dart';
import 'package:hermes_mobile/core/demo/demo_workspace_files.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/network/gateway_auth.dart';
import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';

/// See `demo_gateway_server_test.dart` — `flutter_test` fakes every
/// `HttpClient` with one that always returns 400; this suite talks to a real
/// loopback server, so its bodies run with the genuine platform client.
class _RealHttpOverrides extends HttpOverrides {}

Future<void> _withRealHttp(Future<void> Function() body) {
  return HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      );

  final secureValues = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = call.arguments;
          final key = args is Map ? args['key'] as String? : null;
          switch (call.method) {
            case 'read':
              return key == null ? null : secureValues[key];
            case 'write':
              if (key != null) {
                secureValues[key] = (args as Map)['value'] as String;
              }
              return null;
            case 'delete':
              if (key != null) secureValues.remove(key);
              return null;
            case 'deleteAll':
              secureValues.clear();
              return null;
            case 'containsKey':
              return key != null && secureValues.containsKey(key);
            case 'readAll':
              return secureValues;
            default:
              return null;
          }
        },
      );

  // ── Detection over the seeded transcript ───────────────────────────────

  group('seeded artifact session', () {
    final now = DateTime.now();
    final session = DemoFixtures.latencyReviewSessionForTests(now);

    /// The seeded messages as the app sees them — through the same
    /// `HermesMessage.fromJson` the wire response is parsed with, so the test
    /// exercises the real path from fixture to detector.
    List<HermesMessage> parsed() => [
      for (final m in session.messages)
        HermesMessage.fromJson(m.toJson(session.id)),
    ];

    List<DetectedArtifact> detectAll() => [
      for (final m in parsed()) ...detectArtifactsInMessage(m),
    ];

    test('is paused for v1 — not part of the seeded session list, so its chips '
        'are unreachable from the drawer (see kArtifactViewerEnabled)', () {
      final sessions = DemoFixtures.buildSessions(now);
      expect(sessions.any((s) => s.id == 'demo-latency-review'), isFalse);
    });

    test('the real detector finds both artifacts in the transcript', () {
      final detected = detectAll();

      final markdown = detected.where(
        (a) => a.path == DemoWorkspaceFiles.latencyReviewMarkdownPath,
      );
      expect(
        markdown,
        isNotEmpty,
        reason: 'the write_file tool result must raise a Markdown chip',
      );
      expect(markdown.first.kind, ArtifactFileKind.markdown);
      expect(markdown.first.name, 'latency-review.md');

      final html = detected.where(
        (a) => a.path == DemoWorkspaceFiles.latencyReportHtmlPath,
      );
      expect(
        html,
        isNotEmpty,
        reason: 'the write_file tool result must raise an HTML chip',
      );
      expect(html.first.kind, ArtifactFileKind.html);
      expect(html.first.name, 'latency-report.html');
    });

    test('the write_file and patch tool results each raise a chip', () {
      final writes = parsed().where((m) => m.toolName == 'write_file');
      expect(writes, hasLength(2));
      for (final m in writes) {
        expect(
          detectArtifactsInMessage(m),
          hasLength(1),
          reason: 'each write_file result names exactly one artifact',
        );
      }

      final patch = parsed().firstWhere((m) => m.toolName == 'patch');
      final fromPatch = detectArtifactsInMessage(patch);
      expect(fromPatch, hasLength(1));
      expect(
        fromPatch.single.path,
        DemoWorkspaceFiles.latencyReviewMarkdownPath,
      );
      expect(fromPatch.single.origin, ArtifactOrigin.toolResult);
    });

    test('the shell tool result raises no chip', () {
      final shell = parsed().firstWhere((m) => m.toolName == 'shell');
      expect(detectArtifactsInMessage(shell), isEmpty);
    });

    test('every detected path is one the demo gateway actually serves', () {
      // The backticked filenames in the assistant replies are detected too,
      // and resolve relative to the workspace root — this is the assertion
      // that keeps a chip from ever 404ing on tap.
      final index = DemoWorkspaceFiles.buildIndex(now);
      final detected = detectAll();
      expect(detected, isNotEmpty);
      for (final artifact in detected) {
        final resolved = DemoWorkspaceFiles.resolve(artifact.path);
        expect(
          resolved,
          isNotNull,
          reason: '${artifact.path} escaped the workspace root',
        );
        expect(
          index.containsKey(resolved),
          isTrue,
          reason: '${artifact.path} resolved to $resolved, which is not served',
        );
      }
    });

    test('the seeded byte counts match the files that get served', () {
      final index = DemoWorkspaceFiles.buildIndex(now);
      final writes = parsed().where((m) => m.toolName == 'write_file').toList();
      for (final m in writes) {
        final artifact = detectArtifactsInMessage(m).single;
        final file = index[artifact.path]!;
        expect(m.content, contains('"bytes_written":${file.size}'));
      }
    });
  });

  // ── The files surface, driven by the app's own client ──────────────────

  group('GET /api/files/read', () {
    late DemoGatewayServer server;
    late Uri baseUrl;

    setUp(() async {
      server = DemoGatewayServer(demoSpeedFactor: 0.15);
      baseUrl = await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    Future<DashboardClient> loggedInClient() async {
      final profile = ConnectionProfile(
        id: 'demo-files-${DateTime.now().microsecondsSinceEpoch}',
        baseUrl: baseUrl.toString(),
      );
      final jar = await GatewayAuthClient.persistentJar(profile.id);
      final auth = GatewayAuthClient(
        baseUrl: baseUrl.toString(),
        cookieJar: jar,
      );
      await auth.passwordLogin(
        provider: 'demo',
        username: demoUsername,
        password: demoPassword,
      );
      return DashboardClient(profile: profile);
    }

    test(
      'serves the Markdown artifact as text/markdown',
      () => _withRealHttp(() async {
        final dashboard = await loggedInClient();
        final content = await dashboard.readManagedFile(
          DemoWorkspaceFiles.latencyReviewMarkdownPath,
        );

        expect(content.name, 'latency-review.md');
        expect(content.path, DemoWorkspaceFiles.latencyReviewMarkdownPath);
        expect(content.mimeType, 'text/markdown');

        final text = content.decodeText();
        expect(text, startsWith('# Gateway latency review'));
        // The renderer exercises: headings, lists, a table, a blockquote,
        // inline code, and a fenced code block.
        expect(text, contains('\n## '));
        expect(text, contains('\n### '));
        expect(text, contains('\n- '));
        expect(text, contains('\n| Endpoint |'));
        expect(text, contains('\n> '));
        expect(text, contains('```bash'));
        expect(text, contains('`persist`'));
        // The seeded `patch` message claims this note was added.
        expect(text, contains('the cache is cold'));
        expect(content.size, greaterThan(0));
      }),
    );

    test(
      'serves the HTML artifact as text/html, self-contained and JS-free',
      () => _withRealHttp(() async {
        final dashboard = await loggedInClient();
        final content = await dashboard.readManagedFile(
          DemoWorkspaceFiles.latencyReportHtmlPath,
        );

        expect(content.name, 'latency-report.html');
        expect(content.mimeType, 'text/html');

        final html = content.decodeText();
        expect(html, contains('<style>'));
        expect(html, contains('<svg'));
        // The viewer's CSP is `default-src 'none'` with assets limited to
        // `data:` and no `connect-src`: anything remote would silently fail
        // to load, and any script would need the user to opt in. So the
        // document must reference no external origin and run no JS.
        expect(html, isNot(contains('<script')));
        expect(html, isNot(contains('http://')));
        expect(html, isNot(contains('https://')));
        expect(html, isNot(contains('//fonts.')));
        expect(html, isNot(contains('@import')));
      }),
    );

    test(
      '404s an unknown path, and a relative path resolves against the root',
      () => _withRealHttp(() async {
        final dashboard = await loggedInClient();

        await expectLater(
          dashboard.readManagedFile(DemoWorkspaceFiles.absentPath),
          throwsA(
            isA<ManagedFileException>().having(
              (e) => e.kind,
              'kind',
              ManagedFileErrorKind.notFound,
            ),
          ),
        );

        // A bare filename (what a backticked mention in assistant prose
        // yields) resolves relative to the workspace root, like the real
        // gateway's managed-files root does.
        final relative = await dashboard.readManagedFile('latency-review.md');
        expect(relative.path, DemoWorkspaceFiles.latencyReviewMarkdownPath);
      }),
    );

    test(
      '403s credential material and anything outside the workspace root',
      () => _withRealHttp(() async {
        final dashboard = await loggedInClient();

        await expectLater(
          dashboard.readManagedFile(DemoWorkspaceFiles.sensitivePath),
          throwsA(
            isA<ManagedFileException>().having(
              (e) => e.kind,
              'kind',
              ManagedFileErrorKind.forbidden,
            ),
          ),
        );

        await expectLater(
          dashboard.readManagedFile('../../etc/passwd'),
          throwsA(
            isA<ManagedFileException>().having(
              (e) => e.kind,
              'kind',
              ManagedFileErrorKind.forbidden,
            ),
          ),
        );
      }),
    );

    test(
      'a malformed request is answered, not fatal to the server',
      () => _withRealHttp(() async {
        final client = HttpClient();
        addTearDown(client.close);

        // No `path` at all — FastAPI would reject this before the handler.
        final req = await client.getUrl(
          baseUrl.replace(path: '/api/files/read'),
        );
        req.cookies.add(Cookie('hermes_session_at', 'x'));
        final res = await req.close();
        expect(res.statusCode, 422);
        await res.drain<void>();

        // …and the server is still serving.
        final dashboard = await loggedInClient();
        final content = await dashboard.readManagedFile(
          DemoWorkspaceFiles.latencyReviewMarkdownPath,
        );
        expect(content.size, greaterThan(0));
      }),
    );
  });
}
