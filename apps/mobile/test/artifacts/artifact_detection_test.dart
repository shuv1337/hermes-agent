import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/features/artifacts/artifact_detection.dart';

HermesMessage _tool({
  required String toolName,
  required Map<String, dynamic> result,
  String id = 'm1',
}) {
  return HermesMessage(
    id: id,
    sessionId: 's1',
    role: 'tool',
    toolName: toolName,
    content: jsonEncode(result),
  );
}

HermesMessage _assistant(String text, {String id = 'm1'}) {
  return HermesMessage(
    id: id,
    sessionId: 's1',
    role: 'assistant',
    content: text,
  );
}

/// A session index that knows [paths] were written — the shorthand every
/// prose test needs, since a mention only chips when it correlates to a real
/// `write_file`/`patch` result.
SessionArtifactPaths _known(List<String> paths) {
  return SessionArtifactPaths.fromMessages([
    for (var i = 0; i < paths.length; i++)
      _tool(
        toolName: 'write_file',
        result: {'resolved_path': paths[i]},
        id: 'w$i',
      ),
  ]);
}

void main() {
  group('tool-result detection (write_file / patch)', () {
    test(
      'write_file success with resolved_path .md surfaces a markdown artifact',
      () {
        final msg = _tool(
          toolName: 'write_file',
          result: {
            'bytes_written': 42,
            'verified': true,
            'resolved_path': '/home/user/.hermes/workspace/notes/report.md',
            'files_modified': ['/home/user/.hermes/workspace/notes/report.md'],
          },
        );
        final artifacts = detectArtifactsInMessage(msg);
        expect(artifacts, hasLength(1));
        expect(
          artifacts.single.path,
          '/home/user/.hermes/workspace/notes/report.md',
        );
        expect(artifacts.single.name, 'report.md');
        expect(artifacts.single.kind, ArtifactFileKind.markdown);
        expect(artifacts.single.origin, ArtifactOrigin.toolResult);
      },
    );

    test(
      'patch success with files_created .html surfaces an html artifact',
      () {
        final msg = _tool(
          toolName: 'patch',
          result: {
            'success': true,
            'diff': '--- a\n+++ b\n',
            'files_created': ['/tmp/site/index.html'],
          },
        );
        final artifacts = detectArtifactsInMessage(msg);
        expect(artifacts, hasLength(1));
        expect(artifacts.single.kind, ArtifactFileKind.html);
        expect(artifacts.single.name, 'index.html');
      },
    );

    test('.htm is recognized as html, .markdown as markdown', () {
      final htm = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/tmp/a.htm'},
      );
      final markdown = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/tmp/b.markdown'},
      );
      expect(detectArtifactsInMessage(htm).single.kind, ArtifactFileKind.html);
      expect(
        detectArtifactsInMessage(markdown).single.kind,
        ArtifactFileKind.markdown,
      );
    });

    test('a failed write (truthy error field) never surfaces a chip', () {
      final msg = _tool(
        toolName: 'write_file',
        result: {
          'error':
              'Refusing to write internal read_file display text as file content.',
          'resolved_path': '/tmp/would-have-been.md',
        },
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('a falsy error field is a success, not a failure', () {
      // `'$error'` renders the JSON literal `false` as the *non-empty* string
      // `"false"`, so a stringified check suppressed the chip for a perfectly
      // ordinary success shape. Same for `0` and for the empty
      // list/map some tools use to mean "no errors".
      for (final falsy in [false, 0, <dynamic>[], <String, dynamic>{}]) {
        final msg = _tool(
          toolName: 'write_file',
          result: {'error': falsy, 'resolved_path': '/tmp/report.md'},
        );
        expect(detectArtifactsInMessage(msg).map((a) => a.name), [
          'report.md',
        ], reason: 'error: $falsy');
      }
    });

    test('other truthy error shapes still suppress the chip', () {
      for (final truthy in [
        true,
        1,
        ['boom'],
        {'code': 5},
      ]) {
        final msg = _tool(
          toolName: 'write_file',
          result: {'error': truthy, 'resolved_path': '/tmp/report.md'},
        );
        expect(
          detectArtifactsInMessage(msg),
          isEmpty,
          reason: 'error: $truthy',
        );
      }
    });

    test('non-artifact extensions (.txt, .py) never surface a chip', () {
      final txt = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/tmp/notes.txt'},
      );
      final py = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/tmp/script.py'},
      );
      expect(detectArtifactsInMessage(txt), isEmpty);
      expect(detectArtifactsInMessage(py), isEmpty);
    });

    test('tool names outside the write allow-list never surface a chip, even '
        'with an identically-shaped result payload', () {
      final msg = _tool(
        toolName: 'read_file',
        result: {'resolved_path': '/tmp/report.md', 'path': '/tmp/report.md'},
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('bash/terminal-shaped tool results with an incidental "path" key '
        'never surface a chip (narrowed vs. Desktop\'s KEY_HINT_RE)', () {
      final msg = _tool(
        toolName: 'terminal',
        result: {'path': '/tmp/report.md', 'stdout': 'ok', 'exit_code': 0},
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('non-JSON tool content does not throw and yields no artifacts', () {
      final msg = HermesMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'tool',
        toolName: 'write_file',
        content: 'LINE_NUM|not json at all',
      );
      expect(() => detectArtifactsInMessage(msg), returnsNormally);
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('files_modified mixing artifact and non-artifact paths keeps only '
        'the matching ones, deduplicated', () {
      final msg = _tool(
        toolName: 'patch',
        result: {
          'success': true,
          'files_modified': [
            '/tmp/report.md',
            '/tmp/report.md',
            '/tmp/data.json',
            '/tmp/page.html',
          ],
        },
      );
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts.map((a) => a.name).toSet(), {'report.md', 'page.html'});
    });

    test('function role (legacy tool alias) is treated the same as tool', () {
      final msg = HermesMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'function',
        toolName: 'write_file',
        content: jsonEncode({'resolved_path': '/tmp/report.md'}),
      );
      expect(detectArtifactsInMessage(msg), hasLength(1));
    });
  });

  group('assistant-text detection (backtick spans + @file: refs)', () {
    test('a backtick-quoted path is recognized', () {
      final msg = _assistant('Saved the summary to `notes/report.md` for you.');
      final artifacts = detectArtifactsInMessage(
        msg,
        known: _known(['notes/report.md']),
      );
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, 'notes/report.md');
      expect(artifacts.single.name, 'report.md');
      expect(artifacts.single.origin, ArtifactOrigin.textMention);
    });

    test('a backtick-quoted path containing spaces is recognized and its '
        'display name is just the final path segment', () {
      final msg = _assistant(
        'It is at `/tmp/My Reports/quarterly summary.md`.',
      );
      final artifacts = detectArtifactsInMessage(
        msg,
        known: _known(['/tmp/My Reports/quarterly summary.md']),
      );
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, '/tmp/My Reports/quarterly summary.md');
      expect(artifacts.single.name, 'quarterly summary.md');
    });

    test('merely mentioning a filename in prose — no backticks, no @file: — '
        'never surfaces a chip', () {
      final msg = _assistant(
        'I would normally save this as report.md but nothing was written.',
      );
      expect(
        detectArtifactsInMessage(msg, known: _known(['/ws/report.md'])),
        isEmpty,
      );
    });

    test('a backtick span with a non-artifact extension is ignored', () {
      final msg = _assistant('See `notes.txt` and `script.py` for details.');
      expect(
        detectArtifactsInMessage(
          msg,
          known: _known(['/ws/notes.txt', '/ws/script.py']),
        ),
        isEmpty,
      );
    });

    test('a backtick-quoted http(s) URL is not treated as a local file', () {
      final msg = _assistant('Docs: `https://example.com/report.md`');
      expect(
        detectArtifactsInMessage(msg, known: _known(['/ws/report.md'])),
        isEmpty,
      );
    });

    test('an unquoted @file: ref is recognized', () {
      final msg = _assistant('Have a look: @file:reports/summary.md');
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, 'reports/summary.md');
      expect(artifacts.single.origin, ArtifactOrigin.fileRef);
    });

    test('a backtick-quoted @file: ref (path with spaces) is unquoted '
        'correctly, mirroring the gateway\'s _format_ref_value quoting', () {
      final msg = _assistant(
        'See @file:`my reports/summary.md` for the write-up.',
      );
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, 'my reports/summary.md');
    });

    test('a double-quoted @file: ref is unquoted correctly', () {
      final msg = _assistant(
        'See @file:"my reports/summary.md" for the write-up.',
      );
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, 'my reports/summary.md');
    });

    test(
      'duplicate mentions of the same file in one message dedupe to one chip',
      () {
        final msg = _assistant(
          'Wrote `notes/report.md`. Again, see `notes/report.md` for the full text.',
        );
        expect(
          detectArtifactsInMessage(msg, known: _known(['notes/report.md'])),
          hasLength(1),
        );
      },
    );

    test('two mentions of the same file — one bare, one full — dedupe to one '
        'chip, because both resolve to the same written path', () {
      final msg = _assistant(
        'Wrote `report.md`; the full path is `/ws/notes/report.md`.',
      );
      final artifacts = detectArtifactsInMessage(
        msg,
        known: _known(['/ws/notes/report.md']),
      );
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, '/ws/notes/report.md');
    });

    test('multiple distinct artifacts in one message are all recognized', () {
      final msg = _assistant('Wrote `report.md` and `dashboard.html`.');
      final artifacts = detectArtifactsInMessage(
        msg,
        known: _known(['/ws/report.md', '/ws/site/dashboard.html']),
      );
      expect(artifacts.map((a) => a.name).toSet(), {
        'report.md',
        'dashboard.html',
      });
      expect(artifacts.map((a) => a.path).toSet(), {
        '/ws/report.md',
        '/ws/site/dashboard.html',
      });
    });
  });

  // The defect this correlation exists for: a bare `summary.md` in prose has
  // no directory, so chipping it verbatim sends `?path=summary.md`, which the
  // gateway resolves against the managed-workspace *root* and 404s whenever
  // the agent actually wrote `reports/summary.md`.
  group('prose mentions correlate against the session\'s written paths', () {
    test('a file written into a subdirectory and later mentioned bare chips '
        'the resolved path, not the bare filename', () {
      final write = _tool(
        toolName: 'write_file',
        result: {
          'bytes_written': 128,
          'resolved_path': '/home/u/.hermes/workspace/reports/summary.md',
        },
        id: 'w1',
      );
      final prose = _assistant(
        'Done — the write-up is in `summary.md`.',
        id: 'a1',
      );
      final known = SessionArtifactPaths.fromMessages([write, prose]);

      final artifacts = detectArtifactsInMessage(prose, known: known);
      expect(artifacts, hasLength(1));
      expect(
        artifacts.single.path,
        '/home/u/.hermes/workspace/reports/summary.md',
      );
      expect(artifacts.single.name, 'summary.md');
      expect(artifacts.single.origin, ArtifactOrigin.textMention);
    });

    test('a prose mention with no corresponding tool result produces no chip, '
        'rather than one that 404s on tap', () {
      final write = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/ws/reports/summary.md'},
        id: 'w1',
      );
      final prose = _assistant(
        'Also see `changelog.md` for context.',
        id: 'a1',
      );
      final known = SessionArtifactPaths.fromMessages([write, prose]);

      expect(detectArtifactsInMessage(prose, known: known), isEmpty);
    });

    test('with no session context at all, prose mentions raise no chips '
        '(the default index is empty and therefore fail-safe)', () {
      final prose = _assistant('Saved to `summary.md`.');
      expect(detectArtifactsInMessage(prose), isEmpty);
    });

    test('the tool result itself still chips directly — correlation only '
        'gates prose', () {
      final write = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/ws/reports/summary.md'},
        id: 'w1',
      );
      final artifacts = detectArtifactsInMessage(
        write,
        known: SessionArtifactPaths.fromMessages([write]),
      );
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, '/ws/reports/summary.md');
      expect(artifacts.single.origin, ArtifactOrigin.toolResult);
    });

    test('a partial path is matched on a segment boundary', () {
      final known = _known(['/ws/out/reports/summary.md']);
      final msg = _assistant('See `reports/summary.md`.');
      final artifacts = detectArtifactsInMessage(msg, known: known);
      expect(artifacts.single.path, '/ws/out/reports/summary.md');

      // …and a non-boundary suffix is not a match on its own.
      final near = _assistant('See `ports/summary.md`.');
      expect(
        detectArtifactsInMessage(near, known: known).single.path,
        '/ws/out/reports/summary.md',
        reason: 'falls back to the unambiguous basename match',
      );
    });

    test('an ambiguous basename — two written files sharing it — chips '
        'nothing rather than guessing', () {
      final known = _known(['/ws/a/summary.md', '/ws/b/summary.md']);
      final msg = _assistant('Wrote `summary.md`.');
      expect(detectArtifactsInMessage(msg, known: known), isEmpty);

      // Disambiguating with a directory segment brings the chip back.
      final specific = _assistant('Wrote `b/summary.md`.');
      final artifacts = detectArtifactsInMessage(specific, known: known);
      expect(artifacts.single.path, '/ws/b/summary.md');
    });

    test('./ and backslash spellings normalize onto the same written path', () {
      final known = _known([r'C:\ws\reports\summary.md']);
      expect(
        detectArtifactsInMessage(
          _assistant('See `./reports/summary.md`.'),
          known: known,
        ).single.path,
        r'C:\ws\reports\summary.md',
      );
    });

    test('an @file: ref is chipped as written, without correlation — the '
        'gateway mints it workspace-relative and complete', () {
      final msg = _assistant('Attached: @file:attachments/notes.md');
      // Nothing in the session wrote it; it is still a valid ref.
      expect(detectArtifactsInMessage(msg).single.path, 'attachments/notes.md');
    });

    test('a failed write contributes nothing to the index, so prose naming it '
        'raises no chip', () {
      final failed = _tool(
        toolName: 'write_file',
        result: {'error': 'permission denied', 'resolved_path': '/ws/no.md'},
        id: 'w1',
      );
      final prose = _assistant('Wrote `no.md`.', id: 'a1');
      final known = SessionArtifactPaths.fromMessages([failed, prose]);
      expect(known.paths, isEmpty);
      expect(detectArtifactsInMessage(prose, known: known), isEmpty);
    });

    test('only write-allow-listed tools feed the index', () {
      final read = _tool(
        toolName: 'read_file',
        result: {'resolved_path': '/ws/reports/summary.md'},
        id: 't1',
      );
      final known = SessionArtifactPaths.fromMessages([read]);
      expect(known.paths, isEmpty);
      expect(known.isEmpty, isTrue);
      expect(
        detectArtifactsInMessage(_assistant('See `summary.md`.'), known: known),
        isEmpty,
      );
    });

    test('rebuilding from a previous index carries the same paths forward, so '
        'a streaming transcript need not re-decode unchanged tool results', () {
      final write = _tool(
        toolName: 'write_file',
        result: {'resolved_path': '/ws/reports/summary.md'},
        id: 'w1',
      );
      final first = SessionArtifactPaths.fromMessages([write]);
      // Same tool message, new assistant token appended — the shape of every
      // streaming rebuild.
      final second = SessionArtifactPaths.fromMessages([
        write,
        _assistant('Saved to `summary.md`', id: 'a1'),
      ], previous: first);
      expect(second.paths, ['/ws/reports/summary.md']);
      expect(second.resolve('summary.md'), '/ws/reports/summary.md');

      // A dropped tool message drops its paths — the memo never resurrects
      // stale entries.
      final third = SessionArtifactPaths.fromMessages(const [
        HermesMessage(id: 'a1', sessionId: 's1', role: 'assistant'),
      ], previous: second);
      expect(third.paths, isEmpty);
    });
  });

  group('role gating', () {
    test('user messages never surface a chip, even if they contain a '
        'backtick-quoted artifact-looking path', () {
      final msg = HermesMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: 'Please read `report.md` for me.',
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('system messages never surface a chip', () {
      final msg = HermesMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'system',
        content: 'Wrote `report.md`.',
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('a tool message with no toolName never surfaces a chip', () {
      final msg = HermesMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'tool',
        content: jsonEncode({'resolved_path': '/tmp/report.md'}),
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('an assistant message with null content never throws', () {
      final msg = HermesMessage(id: 'm1', sessionId: 's1', role: 'assistant');
      expect(() => detectArtifactsInMessage(msg), returnsNormally);
      expect(detectArtifactsInMessage(msg), isEmpty);
    });
  });
}
