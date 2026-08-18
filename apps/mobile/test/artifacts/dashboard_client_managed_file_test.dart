import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';

/// Returns a fixed status/body for every request — enough to exercise
/// [DashboardClient.readManagedFile]'s response handling without a real
/// gateway. Mirrors `_CountingAdapter` in `test/session_sync_test.dart`.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
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

DashboardClient _clientWith(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://gw.test',
      // Matches DashboardClient._ensureDio()'s own BaseOptions — 4xx
      // must come back as a normal Response (readManagedFile branches
      // on statusCode itself) rather than as a thrown DioException.
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = adapter;
  return DashboardClient(
    profile: const ConnectionProfile(id: 'gw1', baseUrl: 'https://gw.test'),
    dio: dio,
  );
}

void main() {
  group('DashboardClient.readManagedFile', () {
    test(
      '200 decodes name/path/size/mime/dataUrl and the base64 payload',
      () async {
        final dataUrl =
            'data:text/markdown;base64,${base64.encode(utf8.encode('# Hello'))}';
        final adapter = _FixedAdapter(
          200,
          jsonEncode({
            'name': 'report.md',
            'path': '/tmp/report.md',
            'size': 7,
            'mime_type': 'text/markdown',
            'data_url': dataUrl,
          }),
        );
        final client = _clientWith(adapter);

        final content = await client.readManagedFile('/tmp/report.md');

        expect(content.name, 'report.md');
        expect(content.path, '/tmp/report.md');
        expect(content.size, 7);
        expect(content.mimeType, 'text/markdown');
        expect(content.decodeText(), '# Hello');
        expect(adapter.lastRequest?.path, '/api/files/read');
        expect(adapter.lastRequest?.queryParameters['path'], '/tmp/report.md');
        expect(client.lastError, isNull);
      },
    );

    test('404 throws ManagedFileException(notFound)', () async {
      final adapter = _FixedAdapter(
        404,
        jsonEncode({'detail': 'File not found'}),
      );
      final client = _clientWith(adapter);

      await expectLater(
        client.readManagedFile('/tmp/missing.md'),
        throwsA(
          isA<ManagedFileException>().having(
            (e) => e.kind,
            'kind',
            ManagedFileErrorKind.notFound,
          ),
        ),
      );
      expect(client.lastError, isNotNull);
    });

    test(
      '403 throws ManagedFileException(forbidden) for a sensitive path',
      () async {
        final adapter = _FixedAdapter(
          403,
          jsonEncode({'detail': 'Access to sensitive files is not allowed'}),
        );
        final client = _clientWith(adapter);

        await expectLater(
          client.readManagedFile('~/.hermes/auth.json'),
          throwsA(
            isA<ManagedFileException>().having(
              (e) => e.kind,
              'kind',
              ManagedFileErrorKind.forbidden,
            ),
          ),
        );
      },
    );

    test('413 throws ManagedFileException(tooLarge)', () async {
      final adapter = _FixedAdapter(
        413,
        jsonEncode({'detail': 'File is too large'}),
      );
      final client = _clientWith(adapter);

      await expectLater(
        client.readManagedFile('/tmp/huge.html'),
        throwsA(
          isA<ManagedFileException>().having(
            (e) => e.kind,
            'kind',
            ManagedFileErrorKind.tooLarge,
          ),
        ),
      );
    });

    test(
      '401 throws DashboardAuthException like the rest of the client',
      () async {
        final adapter = _FixedAdapter(
          401,
          jsonEncode({'detail': 'unauthorized'}),
        );
        final client = _clientWith(adapter);

        await expectLater(
          client.readManagedFile('/tmp/report.md'),
          throwsA(isA<DashboardAuthException>()),
        );
      },
    );

    test('an unexpected non-JSON 200 body throws instead of returning '
        'garbage content', () async {
      final adapter = _FixedAdapter(200, 'not json');
      final client = _clientWith(adapter);

      await expectLater(
        client.readManagedFile('/tmp/report.md'),
        throwsA(anything),
      );
    });
  });

  group('ManagedFileContent.decodeText', () {
    ManagedFileContent withDataUrl(String dataUrl, {String? mime}) =>
        ManagedFileContent(
          name: 'x.md',
          path: '/tmp/x.md',
          size: 0,
          mimeType: mime ?? 'text/markdown',
          dataUrl: dataUrl,
        );

    test(
      'returns an empty string for a malformed data URL instead of throwing',
      () {
        expect(withDataUrl('not-a-data-url').decodeText(), '');
        expect(withDataUrl('').decodeText(), '');
        expect(withDataUrl('data:text/markdown;base64,%%%%').decodeText(), '');
      },
    );

    test('a data URL that is not base64-encoded is treated as malformed', () {
      // The gateway always base64-encodes; anything else is a response we
      // do not understand, and guessing at it is how content-type confusion
      // starts.
      expect(
        withDataUrl('data:text/html,<script>alert(1)</script>').decodeText(),
        '',
      );
      expect(withDataUrl('notdata:x;base64,aGk=').decodeText(), '');
    });

    test('the declared MIME type does not affect decoding', () {
      // A `.md` artifact whose data URL claims to be HTML still decodes to
      // exactly its bytes — the MIME never gets a vote, here or in the
      // renderer choice (see rendererKindFor).
      final payload = base64.encode(utf8.encode('# just markdown'));
      expect(
        withDataUrl(
          'data:text/html;base64,$payload',
          mime: 'text/html',
        ).decodeText(),
        '# just markdown',
      );
    });

    test('malformed UTF-8 degrades to replacement chars, not a blank file', () {
      final bytes = <int>[...utf8.encode('ok '), 0xFF, ...utf8.encode(' end')];
      final text = withDataUrl(
        'data:text/markdown;base64,${base64.encode(bytes)}',
      ).decodeText();
      expect(text, startsWith('ok '));
      expect(text, endsWith(' end'));
    });
  });
}
