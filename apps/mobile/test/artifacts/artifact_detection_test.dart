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
      final artifacts = detectArtifactsInMessage(msg);
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
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.path, '/tmp/My Reports/quarterly summary.md');
      expect(artifacts.single.name, 'quarterly summary.md');
    });

    test('merely mentioning a filename in prose — no backticks, no @file: — '
        'never surfaces a chip', () {
      final msg = _assistant(
        'I would normally save this as report.md but nothing was written.',
      );
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('a backtick span with a non-artifact extension is ignored', () {
      final msg = _assistant('See `notes.txt` and `script.py` for details.');
      expect(detectArtifactsInMessage(msg), isEmpty);
    });

    test('a backtick-quoted http(s) URL is not treated as a local file', () {
      final msg = _assistant('Docs: `https://example.com/report.md`');
      expect(detectArtifactsInMessage(msg), isEmpty);
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
        expect(detectArtifactsInMessage(msg), hasLength(1));
      },
    );

    test('multiple distinct artifacts in one message are all recognized', () {
      final msg = _assistant('Wrote `report.md` and `dashboard.html`.');
      final artifacts = detectArtifactsInMessage(msg);
      expect(artifacts.map((a) => a.name).toSet(), {
        'report.md',
        'dashboard.html',
      });
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
