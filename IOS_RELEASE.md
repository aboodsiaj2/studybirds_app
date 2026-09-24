# iOS release setup

The Flutter app now includes an iOS target with bundle identifier
`com.studybirds.app`, Face ID permission copy, the Study Birds app icon set,
and the `studybirds://` URL scheme.

Final signing and App Store delivery must be completed on macOS:

1. Open `study_birds_app-main/ios/Runner.xcworkspace` in Xcode.
2. Select the company Apple Developer team under **Signing & Capabilities**.
3. Register `com.studybirds.app` in the Apple Developer portal.
4. Add the production Firebase `GoogleService-Info.plist` before enabling push.
5. Run `flutter build ipa --release` and validate the archive in Xcode.

Apple certificates, provisioning profiles, Firebase files, and App Store API
keys are secrets and must not be committed to Git.
