import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

void main() {
  test('every shipped locale has the community disclaimer', () {
    for (final locale in supportedAppLocales) {
      final copy = lookupAppLocalizations(locale).unofficialDisclaimer;
      expect(copy.trim(), isNotEmpty, reason: locale.toLanguageTag());
      if (locale.languageCode != 'en') {
        expect(
          copy,
          isNot(
            'Unofficial · Community-built · Not affiliated with Nous Research',
          ),
          reason: locale.toLanguageTag(),
        );
      }
    }
  });
}
