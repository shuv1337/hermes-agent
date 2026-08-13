import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/features/sessions/message_markdown.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// The zero-click-beacon suite for the chat transcript.
///
/// Message bodies are written by an LLM and routinely quote text it fetched
/// off the open web, so they are attacker-influenced. Left ungated,
/// `flutter_markdown_plus` hands an `![](https://…)` to `Image.network` the
/// moment the bubble paints — no tap, no consent — which confirms to a third
/// party that the message was opened, leaks the device's public IP and
/// User-Agent, and can be aimed at the user's own LAN.
///
/// The load-bearing assertion in most of these is the pair
/// `find.byType(Image), findsNothing` + an empty request log: no widget that
/// could fetch was built, *and* nothing was actually requested.

const _remote = '![tracker](https://attacker.example/p.png)';

// 1x1 transparent PNG.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// Records every URL `Image.network` opens, and answers it with a real 1x1
/// PNG.
///
/// `NetworkImage` reads its client through
/// [debugNetworkImageHttpClientProvider], so this sees any request the
/// painting layer would make — without it the test binding's own mock would
/// swallow requests silently and "no fetch happened" would be unfalsifiable.
///
/// It answers *successfully* on purpose: a failed load is evicted from
/// Flutter's image cache and retried on the next build, which would make the
/// "one GET across many streaming rebuilds" assertion vacuous.
class _SpyHttpClient implements HttpClient {
  _SpyHttpClient(this.requested);

  final List<Uri> requested;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requested.add(url);
    return _FakeRequest(base64.decode(_pngBase64));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('get', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.bytes);

  final Uint8List bytes;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse implements HttpClientResponse {
  _FakeResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Unwraps the `ResizeImage` that `Image.memory(cacheWidth: …)` installs.
MemoryImage _memoryImageOf(ImageProvider provider) {
  final inner = provider is ResizeImage ? provider.imageProvider : provider;
  return inner as MemoryImage;
}

Widget _wrap(String data, {Key? key}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: supportedAppLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SingleChildScrollView(
        child: MessageMarkdown(key: key, data: data),
      ),
    ),
  );
}

/// A widget test with the network-image spy installed.
///
/// The provider has to be cleared inside the test *body* — the test binding
/// asserts every painting debug variable is back to null before tearDown
/// runs — so it is done here rather than in a `tearDown`.
void _netTest(
  String description,
  Future<void> Function(WidgetTester tester, List<Uri> requested) body,
) {
  testWidgets(description, (tester) async {
    final requested = <Uri>[];
    debugNetworkImageHttpClientProvider = () => _SpyHttpClient(requested);
    try {
      await body(tester, requested);
    } finally {
      debugNetworkImageHttpClientProvider = null;
      imageCache.clear();
      imageCache.clearLiveImages();
    }
  });
}

void main() {
  group('markdownImageDisposition', () {
    test('a data: image is the only source that renders on its own', () {
      expect(
        markdownImageDisposition(
          Uri.parse('data:image/png;base64,$_pngBase64'),
        ),
        MarkdownImageDisposition.inline,
      );
      // `Uri` lower-cases the scheme, so an upper-case one is not a bypass —
      // nor is it a way to smuggle a non-image payload through.
      expect(
        markdownImageDisposition(Uri.parse('DATA:image/gif;base64,R0lGOD')),
        MarkdownImageDisposition.inline,
      );
      expect(
        markdownImageDisposition(Uri.parse('data:text/html,<b>x</b>')),
        MarkdownImageDisposition.blocked,
      );
    });

    test('a public http(s) source is offered, never taken', () {
      for (final url in [
        'https://attacker.example/p.png',
        'http://attacker.example/p.png',
        'HTTPS://Attacker.Example/p.png',
        'https://8.8.8.8/p.png',
      ]) {
        expect(
          markdownImageDisposition(Uri.parse(url)),
          MarkdownImageDisposition.askFirst,
          reason: url,
        );
      }
    });

    test('private/LAN space is not offered at all', () {
      // The SSRF-flavoured case. A tap-to-load prompt naming `192.168.1.1`
      // is not a question a person can answer correctly, and the phone sits
      // on this network by design — so the affordance is withheld, not just
      // gated.
      for (final url in [
        'http://192.168.1.1/admin?reboot=1',
        'http://10.0.0.5/x.png',
        'http://172.16.4.4/x.png',
        'http://169.254.169.254/latest/meta-data/',
        'http://100.100.1.1/x.png', // CGNAT / tailnet
        'http://127.0.0.1:8080/x.png',
        'http://localhost:8080/x.png',
        'http://gateway.local/x.png',
        'https://box.ts.net/x.png',
        'http://[fd00::1]/x.png',
      ]) {
        expect(
          markdownImageDisposition(Uri.parse(url)),
          MarkdownImageDisposition.blockedPrivate,
          reason: url,
        );
      }
    });

    test('everything else is inert — never Image.file, never a fetch', () {
      for (final src in [
        'file:///etc/hosts',
        '../../secret.png',
        '/var/mobile/pic.png',
        'relative.png',
        '//attacker.example/p.png', // protocol-relative
        'resource:assets/x.png',
        'content://com.android.providers/x',
        'javascript:alert(1)',
        'http://', // no host
      ]) {
        expect(
          markdownImageDisposition(Uri.parse(src)),
          MarkdownImageDisposition.blocked,
          reason: src,
        );
      }
    });
  });

  _netTest('a remote image builds no Image and fetches nothing on first '
      'paint', (tester, requested) async {
    await tester.pumpWidget(_wrap('Here you go:\n\n$_remote\n'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(requested, isEmpty);
    // The host is surfaced so the user can see *who* they'd be calling.
    expect(
      find.text('Tap to load image from attacker.example'),
      findsOneWidget,
    );
  });

  _netTest('tapping the placeholder is what performs the request', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(_wrap(_remote));
    await tester.pump();
    expect(requested, isEmpty);

    await tester.tap(find.text('Tap to load image from attacker.example'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(requested.single, Uri.parse('https://attacker.example/p.png'));
  });

  _netTest('a granted load survives the streaming re-render, and is not '
      'inherited by a fresh widget', (tester, requested) async {
    await tester.pumpWidget(
      _wrap('Partial $_remote', key: const ValueKey('a')),
    );
    await tester.pump();
    await tester.tap(find.text('Tap to load image from attacker.example'));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    // Streaming: the body grows by a token, MarkdownBody re-parses and
    // rebuilds every child. The consent lives in the MessageMarkdown state,
    // so the image must not flip back to a placeholder.
    for (final token in [' and', ' then', ' done']) {
      await tester.pumpWidget(
        _wrap('Partial $_remote$token', key: const ValueKey('a')),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget, reason: token);
      expect(find.textContaining('Tap to load'), findsNothing, reason: token);
    }
    // One fetch total across all those rebuilds.
    expect(requested, hasLength(1));

    // A different key means a different State: consent is per view and is
    // never persisted, so this one starts inert again.
    await tester.pumpWidget(_wrap(_remote, key: const ValueKey('b')));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(
      find.text('Tap to load image from attacker.example'),
      findsOneWidget,
    );
    expect(requested, hasLength(1));
  });

  _netTest('a LAN image gets no tap-to-load affordance at all', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(_wrap('![x](http://192.168.1.1/admin?reboot=1)'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(requested, isEmpty);
    expect(find.textContaining('Tap to load'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(
      find.text('Image blocked — private network (192.168.1.1)'),
      findsOneWidget,
    );
  });

  _netTest('file:, relative and unknown-scheme sources stay inert', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(
      _wrap(
        '![a](file:///etc/hosts)\n\n![b](../../secret.png)\n\n'
        '![c](//attacker.example/p.png)\n\n![d](resource:assets/x.png)\n',
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(requested, isEmpty);
    expect(find.text('Image blocked — unsupported source'), findsNWidgets(4));
    expect(find.byType(InkWell), findsNothing);
  });

  _netTest('data: images still render inline, with no network', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(
      _wrap('![logo](data:image/png;base64,$_pngBase64)'),
    );
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    // `cacheWidth` wraps the provider in a `ResizeImage`, so the decode is
    // capped at the screen's physical width instead of the image's own
    // dimensions — the bytes underneath are still a `MemoryImage`, i.e. still
    // no socket.
    expect(images.single.image, isA<ResizeImage>());
    expect(_memoryImageOf(images.single.image), isA<MemoryImage>());
    expect(requested, isEmpty);
  });

  _netTest('a re-rendered data: image reuses one decoded byte list', (
    tester,
    requested,
  ) async {
    // MemoryImage keys the image cache on byte-list *identity*; a fresh
    // decode per streamed token would re-decode the picture every time.
    const image = '![logo](data:image/png;base64,$_pngBase64)';
    await tester.pumpWidget(_wrap(image));
    await tester.pump();
    final first = tester.widget<Image>(find.byType(Image)).image;

    await tester.pumpWidget(_wrap('$image more'));
    await tester.pump();
    final second = tester.widget<Image>(find.byType(Image)).image;

    expect(
      identical(_memoryImageOf(first).bytes, _memoryImageOf(second).bytes),
      isTrue,
    );
    expect(first, second); // cache hit, no second decode
  });

  _netTest('an oversized data: payload is refused before it is decoded', (
    tester,
    requested,
  ) async {
    // `data:` is the one disposition that renders on paint, and the decode is
    // synchronous inside `build()`. An LLM-written message quoting a 20 MB
    // inline PNG would otherwise block the frame, and 24 of them used to be
    // allowed to sit in the module-level cache — ~1 GB retained behind a
    // limit that counted *entries*.
    //
    // The cap is applied to the encoded URI length, so this string never
    // reaches `contentAsBytes()`. It stays a valid base64 image URI: the
    // refusal must come from the size, not from a parse failure.
    final huge = 'A' * (3 * 1024 * 1024);
    await tester.pumpWidget(_wrap('![big](data:image/png;base64,$huge)'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Image blocked — unsupported source'), findsOneWidget);
    expect(requested, isEmpty);
  });

  _netTest('a data: image just under the cap still renders', (
    tester,
    requested,
  ) async {
    // The other side of the cap — the guard must not have swallowed ordinary
    // inline images. 1 MB of base64 decodes to ~768 KB, comfortably under.
    final ok = 'A' * (1024 * 1024);
    await tester.pumpWidget(_wrap('![fine](data:image/png;base64,$ok)'));
    await tester.pump();

    // The bytes are not a real PNG, so the decode fails at the *image* layer
    // and `errorBuilder` runs — but an `Image` widget was built, which is
    // exactly what the size gate is being asked not to prevent.
    expect(find.byType(Image), findsOneWidget);
    expect(requested, isEmpty);
  });

  _netTest('raw HTML in a message never becomes a fetching widget', (
    tester,
    requested,
  ) async {
    // The transcript has no HTML renderer: `flutter_markdown_plus` parses
    // with `encodeHtml: false` and its builder only ever emits widgets for
    // markdown elements, so raw tags land as literal text (or are dropped).
    // Nothing here may resolve to an `Image`.
    await tester.pumpWidget(
      _wrap(
        'text <img src="https://attacker.example/h.png"> more\n\n'
        '<img src="https://attacker.example/block.png">\n\n'
        '<link rel="stylesheet" href="https://attacker.example/s.css">\n\n'
        '<style>@import url(https://attacker.example/f.css);</style>\n\n'
        '<iframe src="https://attacker.example/i"></iframe>\n',
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(requested, isEmpty);
  });

  _netTest('a link is not prefetched — only tapping one acts', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(
      _wrap(
        '[click](https://attacker.example/l) and '
        '<https://attacker.example/auto>\n',
      ),
    );
    await tester.pump();

    expect(requested, isEmpty);
    expect(find.byType(Image), findsNothing);
  });

  _netTest('an image inside a fenced code block renders as code', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(_wrap('```markdown\n$_remote\n```\n'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(requested, isEmpty);
    expect(find.textContaining('attacker.example'), findsWidgets);
  });

  _netTest('a data: URI whose payload is not an image is refused', (
    tester,
    requested,
  ) async {
    await tester.pumpWidget(
      _wrap('![x](data:text/html;base64,${base64.encode(utf8.encode('<b>'))})'),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Image blocked — unsupported source'), findsOneWidget);
  });
}
