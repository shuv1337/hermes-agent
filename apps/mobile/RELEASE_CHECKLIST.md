# Hermes Go release checklist

The source tree builds successfully for Android and iOS, but a store submission
also depends on publisher-owned accounts, policies, credentials, and a live
review environment. Complete this checklist for each release candidate.

## Required before submission

- [ ] Publish a privacy policy at a stable public HTTPS URL.
- [ ] Add that URL to App Store Connect, Play Console, and an easily accessible
      location inside the app by compiling with
      `--dart-define=HERMES_PRIVACY_POLICY_URL=https://…`.
- [ ] Prepare a reviewer-accessible HTTPS Hermes gateway and temporary test
      credentials. Include concise connection and feature-review instructions.
- [ ] Confirm the publisher has the right to use the Hermes name, icon, and all
      bundled artwork in commercial store listings.
- [ ] Complete App Store privacy answers and Google Play Data safety answers
      from the shipped build's real behavior.
- [ ] Prepare localized store description, support URL, category, age rating,
      screenshots, phone/tablet declarations, and contact details.
- [ ] Test login, session sync, chat/tool streaming, attachments, jobs,
      notifications, reconnect, background catch-up, and Disconnect against a
      production-like gateway on physical iOS and Android devices.
- [ ] Test Dynamic Type / Android font scale at the largest supported setting,
      landscape and small screens, right-to-left Arabic, keyboard navigation,
      and every shipped locale. Confirm no critical action is clipped or
      inaccessible.

## Android signing and Play Console

The release Gradle configuration never falls back to the debug key. Without a
publisher key, `flutter build appbundle --release` intentionally produces an
unsigned bundle.

1. Create and securely back up an upload keystore outside source control.
2. Copy `android/key.properties.example` to `android/key.properties` and fill
   in the absolute keystore path and credentials.
3. Build and verify:

   ```bash
   flutter build appbundle --release \
     --dart-define=HERMES_PRIVACY_POLICY_URL=https://publisher.example/privacy
   jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
   ```

4. Enroll in Play App Signing and upload the signed AAB.
5. Verify the final Play pre-launch report on supported Android API levels.

Do not commit the keystore or `key.properties`.

## Apple signing and App Store Connect

- [ ] Confirm the production bundle identifier, Apple Developer team,
      capabilities, signing certificate, and distribution provisioning profile.
- [ ] Archive with Xcode or `flutter build ipa --release` using distribution
      signing and the `HERMES_PRIVACY_POLICY_URL` Dart define, then validate the
      archive before upload.
- [ ] Test the exact TestFlight build, including notification permission timing
      and background behavior.
- [ ] Provide App Review with the HTTPS gateway URL, temporary credentials, and
      any steps needed to reach representative sessions/jobs.

Hermes Go does not create a Hermes account. If account creation is added later,
implement in-app account deletion before submission rather than treating local
Disconnect as server-side deletion.

## Release gates

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
(cd android && ./gradlew :app:lintRelease)
flutter build appbundle --release \
  --dart-define=HERMES_PRIVACY_POLICY_URL=https://publisher.example/privacy
flutter build ios --release --no-codesign \
  --dart-define=HERMES_PRIVACY_POLICY_URL=https://publisher.example/privacy
```

Also inspect both merged Android permissions and the signed Apple archive.
Dependency or SDK upgrades should repeat the full physical-device and store
validation pass.
