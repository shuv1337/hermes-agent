import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/theme/hermes_skins.dart';
import 'package:hermes_mobile/features/sessions/message_markdown.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

const _fenceMarkdown = '''
```rust
fn main() {
    println!("hi");
}
```
''';

/// WCAG relative-luminance contrast ratio (1.0 = identical, 21.0 = max).
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<({Color codeBg, Color codeText})> _pumpAndReadCodeColors(
  WidgetTester tester,
  HermesSkin skin,
  Brightness requested,
) async {
  final theme = buildThemeData(skin, requested);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      locale: const Locale('en'),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final fg = Theme.of(context).colorScheme.onSurface;
          return Scaffold(
            body: SingleChildScrollView(
              child: MessageMarkdown(data: _fenceMarkdown, color: fg),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();

  Color? codeBg;
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      codeBg = decoration.color;
    }
  }
  Color? codeText;
  for (final text in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    if (text.data != null) codeText = text.style?.color;
  }

  expect(codeBg, isNotNull, reason: 'code block DecoratedBox not found');
  expect(codeText, isNotNull, reason: 'code block SelectableText not found');
  return (codeBg: codeBg!, codeText: codeText!);
}

void main() {
  // WCAG AA minimum for normal text.
  const minContrast = 4.5;

  testWidgets(
    'fenced code block stays readable for a single-palette (always-dark) '
    'skin even when the theme is resolved into the *light* slot',
    (tester) async {
      // Regression test for the dark-mode-on-device bug: skins with no
      // `darkColors` (midnight/ember/mono/cyberpunk/slate) render the same
      // dark-looking palette in both the light- and dark-theme slots, so
      // `theme.brightness` alone does not reflect what's actually on
      // screen. This reproduces the mismatch directly: request the
      // *light* slot for the `midnight` skin, which desktop-parity design
      // still renders as a dark page (background `#08081c`).
      final colors = await _pumpAndReadCodeColors(
        tester,
        midnightSkin,
        Brightness.light,
      );

      // The container must actually be a dark, elevated surface — not the
      // near-white card the bug produced — so it doesn't wash out the
      // light (onSurface) code text sitting on top of it.
      expect(
        colors.codeBg.computeLuminance(),
        lessThan(0.2),
        reason:
            'code block background should be dark on a dark page; got '
            '${colors.codeBg}',
      );
      expect(
        _contrastRatio(colors.codeBg, colors.codeText),
        greaterThanOrEqualTo(minContrast),
        reason:
            'code block text vs background contrast too low '
            '(bg=${colors.codeBg}, text=${colors.codeText})',
      );
    },
  );

  testWidgets(
    'fenced code block stays readable across every built-in skin in both '
    'theme slots',
    (tester) async {
      for (final skin in kBuiltinSkins) {
        for (final brightness in Brightness.values) {
          final colors = await _pumpAndReadCodeColors(tester, skin, brightness);
          expect(
            _contrastRatio(colors.codeBg, colors.codeText),
            greaterThanOrEqualTo(minContrast),
            reason:
                'skin=${skin.id} requested=$brightness bg=${colors.codeBg} '
                'text=${colors.codeText}',
          );
        }
      }
    },
  );

  testWidgets(
    'light mode (dual-mode Nous skin) keeps a light code surface with dark '
    'text — no regression from the dark-mode fix',
    (tester) async {
      final colors = await _pumpAndReadCodeColors(
        tester,
        nousSkin,
        Brightness.light,
      );
      expect(
        colors.codeBg.computeLuminance(),
        greaterThan(0.6),
        reason: 'nous light-mode code surface should stay light',
      );
      expect(
        _contrastRatio(colors.codeBg, colors.codeText),
        greaterThanOrEqualTo(minContrast),
      );
    },
  );
}
