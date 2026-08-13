import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';
import 'package:hermes_mobile/features/artifacts/artifact_sandbox.dart';

/// Adversarial tests for the artifact sandbox. Everything under test is a
/// pure function, so the hostile-input cases that a real WebView would be
/// needed to observe (does the CSP actually apply? is that scheme refused?)
/// are checked here instead.
///
/// The invariant each HTML case asserts is the one that matters: the policy
/// `<meta>` is inside a `<head>` **we** wrote and precedes every byte the
/// artifact supplied — no matter what the artifact does to confuse a parser.
void main() {
  group('artifactCsp', () {
    test('forbids script entirely while JavaScript is off', () {
      final csp = artifactCsp(allowScripts: false);
      expect(csp, contains("script-src 'none'"));
      expect(csp, isNot(contains("script-src 'unsafe-inline'")));
    });

    test('permits only the document\'s own inline script when JS is on', () {
      final csp = artifactCsp(allowScripts: true);
      expect(csp, contains("script-src 'unsafe-inline'"));
      // No host source may ever appear in script-src: an enabled script must
      // not be able to pull down a second stage.
      expect(csp, isNot(contains('script-src *')));
      expect(csp, isNot(contains('http')));
    });

    test('blocks every network sink in both modes', () {
      for (final allowScripts in [false, true]) {
        final csp = artifactCsp(allowScripts: allowScripts);
        expect(csp, startsWith("default-src 'none';"));
        expect(csp, contains("connect-src 'none'"));
        expect(csp, contains("frame-src 'none'"));
        expect(csp, contains("object-src 'none'"));
        expect(csp, contains("form-action 'none'"));
        expect(csp, contains("base-uri 'none'"));
        expect(csp, contains('img-src data:'));
        expect(csp, contains('font-src data:'));
        expect(csp, contains('media-src data:'));
        // A remote host is never a source for anything.
        expect(csp, isNot(contains('https:')));
      }
    });
  });

  group('sandboxedArtifactHtml', () {
    const cspMarker = '<meta http-equiv="Content-Security-Policy"';

    /// Every hostile document must satisfy the same two properties: the
    /// policy sits in a head we wrote, and the artifact's own bytes appear
    /// verbatim *after* that head — never interleaved with it. Together
    /// those mean no arrangement of the artifact's tags can get in front of
    /// the policy or out of the body.
    void expectSandboxed(String raw, {bool allowScripts = false}) {
      final out = sandboxedArtifactHtml(raw, allowScripts: allowScripts);

      expect(
        out,
        startsWith(
          '<!DOCTYPE html><html><head><meta charset="utf-8">$cspMarker',
        ),
      );
      const headClose = '</head><body>';
      final split = out.indexOf(headClose);
      expect(split, greaterThan(0));
      expect(out.indexOf(cspMarker), lessThan(split));
      expect(out.substring(split + headClose.length), '$raw</body></html>');
    }

    test('a bare fragment is wrapped', () {
      expectSandboxed('<p>hello</p>');
    });

    test('a full document is nested in the body, head and all', () {
      expectSandboxed(
        '<!DOCTYPE html><html><head><title>x</title></head>'
        '<body><p>hi</p></body></html>',
      );
    });

    test('a <header> element cannot masquerade as the head', () {
      // The old injector searched for the literal `<head`, which `<header`
      // matches — the policy landed inside <body>, where a <meta> CSP is
      // ignored by the parser. Wrapping has no such failure mode.
      final out = sandboxedArtifactHtml(
        '<html><body><header>nav</header><script>x()</script></body></html>',
        allowScripts: false,
      );
      expect(out.indexOf(cspMarker), lessThan(out.indexOf('<header')));
      expect(out.indexOf(cspMarker), lessThan(out.indexOf('<script')));
      expectSandboxed(
        '<html><body><header>nav</header><script>x()</script></body></html>',
      );
    });

    test('a <head> inside a comment cannot capture the injection', () {
      expectSandboxed('<!-- <head> --><script>x()</script>');
    });

    test('a <head> inside a script or an attribute value cannot either', () {
      expectSandboxed('<script>var s = "<head>";</script>');
      expectSandboxed('<div data-x="<head>"><script>x()</script></div>');
    });

    test('the document\'s own CSP meta cannot loosen ours', () {
      const hostile =
          '<html><head>'
          '<meta http-equiv="Content-Security-Policy" '
          'content="default-src *; script-src *">'
          '</head><body>x</body></html>';
      final out = sandboxedArtifactHtml(hostile, allowScripts: false);
      // Ours is first and in a real head; theirs is parsed into <body>,
      // where a meta-delivered policy is ignored — and additional policies
      // only ever intersect, so it could not loosen ours regardless.
      expect(out.indexOf(cspMarker), lessThan(out.indexOf('default-src *')));
      expectSandboxed(hostile);
    });

    test('a <base> tag is still covered by base-uri', () {
      final out = sandboxedArtifactHtml(
        '<base href="https://evil.example/">',
        allowScripts: false,
      );
      expect(out, contains("base-uri 'none'"));
      expect(out.indexOf(cspMarker), lessThan(out.indexOf('<base')));
    });

    test('an iframe srcdoc payload is covered by frame-src', () {
      final out = sandboxedArtifactHtml(
        '<iframe srcdoc="&lt;script&gt;x()&lt;/script&gt;"></iframe>',
        allowScripts: true,
      );
      expect(out, contains("frame-src 'none'"));
      expect(out.indexOf(cspMarker), lessThan(out.indexOf('<iframe')));
    });

    test('empty input still produces a policed document', () {
      expectSandboxed('');
    });

    test('script-src tracks the toggle', () {
      expect(
        sandboxedArtifactHtml('<p>x</p>', allowScripts: false),
        contains("script-src 'none'"),
      );
      expect(
        sandboxedArtifactHtml('<p>x</p>', allowScripts: true),
        contains("script-src 'unsafe-inline'"),
      );
    });
  });

  group('decideArtifactNavigation', () {
    test('allows only the about:blank bootstrap', () {
      for (final url in ['about:blank', '', '  ', 'about:blank#top']) {
        expect(
          decideArtifactNavigation(url, scriptsEnabled: false),
          ArtifactNavigationAction.allowInitialLoad,
          reason: url,
        );
      }
      // Other about: URLs are not the bootstrap.
      expect(
        decideArtifactNavigation('about:srcdoc', scriptsEnabled: false),
        ArtifactNavigationAction.block,
      );
    });

    test('offers http(s) as a confirmed hand-off while scripts are off', () {
      for (final url in [
        'https://example.com/a',
        'http://192.168.1.1/admin',
        'HTTPS://Example.com',
      ]) {
        expect(
          decideArtifactNavigation(url, scriptsEnabled: false),
          ArtifactNavigationAction.offerExternalOpen,
          reason: url,
        );
      }
    });

    test('refuses http(s) outright once scripts are on', () {
      // A script can synthesise this navigation with anything it scraped or
      // prompted for in the query string, without a tap — so the hand-off
      // is withdrawn entirely in JS mode.
      expect(
        decideArtifactNavigation(
          'https://evil.example/?leak=secret',
          scriptsEnabled: true,
        ),
        ArtifactNavigationAction.block,
      );
    });

    test('blocks every other scheme rather than handing it to a launcher', () {
      const hostile = [
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'blob:https://example.com/abc',
        'file:///etc/passwd',
        'file:///data/data/com.example/databases/app.db',
        'content://com.android.providers/settings',
        'intent://scan/#Intent;scheme=zxing;end',
        'tel:+15551234567',
        'sms:+15551234567',
        'mailto:someone@example.com',
        'itms-apps://apps.apple.com/app/id1',
        'hermes://profiles/add?url=https://evil.example',
        'ws://example.com/socket',
        'ftp://example.com/x',
        '//evil.example/protocol-relative',
        '/absolute/path',
        'relative.html',
        '#fragment',
      ];
      for (final url in hostile) {
        for (final scripts in [false, true]) {
          expect(
            decideArtifactNavigation(url, scriptsEnabled: scripts),
            ArtifactNavigationAction.block,
            reason: '$url (scripts: $scripts)',
          );
        }
      }
    });

    test('blocks an http URL with no host', () {
      expect(
        decideArtifactNavigation('http://', scriptsEnabled: false),
        ArtifactNavigationAction.block,
      );
    });
  });

  group('rendererKindFor', () {
    test('the extension decides — a MIME type never promotes markdown into '
        'the WebView', () {
      expect(
        rendererKindFor(
          detectedKind: ArtifactFileKind.markdown,
          serverMimeType: 'text/html',
        ),
        ArtifactFileKind.markdown,
      );
      expect(
        rendererKindFor(
          detectedKind: ArtifactFileKind.markdown,
          serverMimeType: 'application/octet-stream',
        ),
        ArtifactFileKind.markdown,
      );
    });

    test('nor does it demote html', () {
      for (final mime in [
        'text/markdown',
        'text/plain',
        null,
        '',
        'text/html; charset=utf-8',
      ]) {
        expect(
          rendererKindFor(
            detectedKind: ArtifactFileKind.html,
            serverMimeType: mime,
          ),
          ArtifactFileKind.html,
          reason: '$mime',
        );
      }
    });
  });

  group('shareMimeTypeFor / safeArtifactFileName', () {
    test('the shared MIME comes from the renderer kind, not the server', () {
      expect(shareMimeTypeFor(ArtifactFileKind.markdown), 'text/markdown');
      expect(shareMimeTypeFor(ArtifactFileKind.html), 'text/html');
    });

    test('a path-like server filename cannot escape the temp directory', () {
      expect(safeArtifactFileName('../../../etc/passwd'), 'passwd');
      expect(safeArtifactFileName(r'..\..\windows\system.ini'), 'system.ini');
      expect(safeArtifactFileName('/tmp/report.md'), 'report.md');
      expect(safeArtifactFileName('report.md'), 'report.md');
      expect(safeArtifactFileName(''), 'artifact');
      expect(safeArtifactFileName('..'), 'artifact');
      expect(safeArtifactFileName('a/..'), 'artifact');
      expect(safeArtifactFileName('re\nport.md'), 'report.md');
    });
  });

  group('sanitizeMarkdownArtifact', () {
    test('a remote image is neutralised into inert source text', () {
      // Zero-click beacon: flutter_markdown_plus would hand this to
      // Image.network on first paint.
      expect(
        sanitizeMarkdownArtifact('![pixel](https://evil.example/p.png)'),
        '`![pixel](https://evil.example/p.png)`',
      );
      expect(
        sanitizeMarkdownArtifact('![x](http://192.168.1.1/router?reboot=1)'),
        '`![x](http://192.168.1.1/router?reboot=1)`',
      );
    });

    test('a title or an angle-bracketed destination does not help', () {
      expect(
        sanitizeMarkdownArtifact('![x](https://evil.example/p.png "hi")'),
        contains('`!['),
      );
      expect(
        sanitizeMarkdownArtifact('![x](<https://evil.example/p.png>)'),
        contains('`!['),
      );
    });

    test('a destination split across lines is still caught', () {
      final out = sanitizeMarkdownArtifact(
        '![x](\nhttps://evil.example/p.png)',
      );
      expect(out, isNot(contains('](\n')));
      expect(out, startsWith('`!['));
    });

    test('local and scheme-relative sources are neutralised too', () {
      // These reach Image.file rather than Image.network, but blocking them
      // keeps the rule "a data: URI or nothing".
      for (final src in [
        'file:///etc/hosts',
        '../../secret.png',
        '/var/mobile/pic.png',
        '//evil.example/p.png',
      ]) {
        expect(
          sanitizeMarkdownArtifact('![x]($src)'),
          '`![x]($src)`',
          reason: src,
        );
      }
    });

    test('self-contained data: images are left alone', () {
      const inline = '![logo](data:image/png;base64,iVBORw0KGgo=)';
      expect(sanitizeMarkdownArtifact(inline), inline);
      const withTitle = '![logo](data:image/png;base64,iVBORw0= "Logo")';
      expect(sanitizeMarkdownArtifact(withTitle), withTitle);
      const angled = '![logo](<data:image/png;base64,iVBORw0=> "Logo")';
      expect(sanitizeMarkdownArtifact(angled), angled);
      const upper = '![logo](DATA:image/png;base64,iVBORw0=)';
      expect(sanitizeMarkdownArtifact(upper), upper);
    });

    test('reference-style images resolve through their definition', () {
      const hostile = '![logo][ref]\n\n[ref]: https://evil.example/p.png\n';
      expect(sanitizeMarkdownArtifact(hostile), contains('`![logo][ref]`'));

      const benign = '![logo][ref]\n\n[ref]: data:image/png;base64,iVBOR\n';
      expect(sanitizeMarkdownArtifact(benign), contains('![logo][ref]'));
      expect(sanitizeMarkdownArtifact(benign), isNot(contains('`![logo')));
    });

    test('a shortcut reference with no definition is neutralised', () {
      expect(sanitizeMarkdownArtifact('![logo]'), '`![logo]`');
    });

    test('links, not images, are untouched', () {
      const doc =
          '[click](https://example.com) and text and `![code](x)` inline.';
      expect(sanitizeMarkdownArtifact(doc), contains('[click](https://'));
    });

    test('images inside fenced code are left verbatim', () {
      const doc =
          'Before\n\n'
          '```markdown\n'
          '![x](https://example.com/p.png)\n'
          '```\n\n'
          'After ![y](https://evil.example/q.png)\n';
      final out = sanitizeMarkdownArtifact(doc);
      expect(
        out,
        contains('```markdown\n![x](https://example.com/p.png)\n```'),
      );
      expect(out, contains('`![y](https://evil.example/q.png)`'));
    });

    test('a document with no images is returned unchanged', () {
      const doc = '# Report\n\nSome **text**.\n\n- a\n- b\n';
      expect(sanitizeMarkdownArtifact(doc), same(doc));
    });

    test('surrounding structure survives the rewrite', () {
      const doc =
          '# Title\n\nIntro ![x](https://e.example/p.png) tail.\n\nEnd\n';
      final out = sanitizeMarkdownArtifact(doc);
      expect(out, startsWith('# Title\n\nIntro `!['));
      expect(out, endsWith(' tail.\n\nEnd\n'));
    });
  });
}
