import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_mobile/core/theme/hermes_skins.dart';

/// WCAG relative-luminance contrast ratio (1.0 = identical, 21.0 = max).
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // WCAG AA minimum for normal text.
  const minContrast = 4.5;

  // Regression coverage for the class of bugs where 5 of 6 built-in skins
  // (midnight/ember/mono/cyberpunk/slate) only define one dark palette, so
  // `paletteFor(brightness)` returns it for *both* the light and dark
  // slots. `buildThemeData` used to build `ColorScheme`/`ThemeData` off the
  // *requested* slot brightness instead of the palette actually rendered,
  // so `theme.brightness` could read `Brightness.light` while every color
  // on screen was dark. Anything that trusts the flag (SnackBar
  // inverseSurface, elevation overlays, AppBar status-bar icon color, text
  // selection defaults, ...) misbehaved. This asserts the flag can never
  // lie again, for every built-in skin in both theme slots.
  for (final skin in kBuiltinSkins) {
    for (final requested in Brightness.values) {
      test('skin=${skin.id} requested=$requested: ThemeData.brightness matches '
          'the actual rendered scaffold surface', () {
        final theme = buildThemeData(skin, requested);

        expect(
          theme.brightness,
          ThemeData.estimateBrightnessForColor(theme.scaffoldBackgroundColor),
          reason:
              'ThemeData.brightness disagrees with the actual '
              'scaffoldBackgroundColor for skin=${skin.id} '
              'requested=$requested (background='
              '${theme.scaffoldBackgroundColor})',
        );

        expect(
          theme.colorScheme.brightness,
          theme.brightness,
          reason:
              'ColorScheme.brightness must match ThemeData.brightness for '
              'skin=${skin.id} requested=$requested',
        );

        expect(
          _contrastRatio(
            theme.colorScheme.onSurface,
            theme.scaffoldBackgroundColor,
          ),
          greaterThanOrEqualTo(minContrast),
          reason:
              'onSurface vs scaffoldBackground contrast too low for '
              'skin=${skin.id} requested=$requested '
              '(onSurface=${theme.colorScheme.onSurface}, '
              'background=${theme.scaffoldBackgroundColor})',
        );

        // Cheap default-derived pairing: SnackBar content vs its own
        // background must stay readable now that its brightness resolves
        // off the real palette instead of the requested slot.
        final snackBg = theme.snackBarTheme.backgroundColor;
        final snackFg = theme.snackBarTheme.contentTextStyle?.color;
        if (snackBg != null && snackFg != null) {
          expect(
            _contrastRatio(snackBg, snackFg),
            greaterThanOrEqualTo(minContrast),
            reason:
                'SnackBar content vs background contrast too low for '
                'skin=${skin.id} requested=$requested '
                '(bg=$snackBg, fg=$snackFg)',
          );
        }
      });
    }
  }
}
