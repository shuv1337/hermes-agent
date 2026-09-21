import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/core/config/release_config.dart';

void main() {
  test('privacy policy parser accepts only valid HTTPS URLs', () {
    expect(
      ReleaseConfig.parsePrivacyPolicyUrl('https://publisher.example/privacy'),
      Uri.parse('https://publisher.example/privacy'),
    );
    expect(
      ReleaseConfig.parsePrivacyPolicyUrl('http://publisher.example/privacy'),
      isNull,
    );
    expect(
      ReleaseConfig.parsePrivacyPolicyUrl(
        'https://user:password@publisher.example/privacy',
      ),
      isNull,
    );
    expect(ReleaseConfig.parsePrivacyPolicyUrl('not a URL'), isNull);
  });

  test('privacy policy is absent unless a valid HTTPS URL is compiled in', () {
    final configured = ReleaseConfig.privacyPolicyUrl.trim();
    final uri = ReleaseConfig.privacyPolicyUri;

    if (configured.isEmpty) {
      expect(uri, isNull);
    } else {
      expect(uri?.scheme, 'https');
      expect(uri?.host, isNotEmpty);
      expect(uri?.userInfo, isEmpty);
    }
  });
}
