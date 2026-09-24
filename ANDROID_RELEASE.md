# Android release setup

The Android application ID is `com.studybirds.app`. Release builds never use
the debug certificate.

## Create the upload key once

Run from `study_birds_app-main/android`:

```powershell
keytool -genkeypair -v -keystore studybirds-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias studybirds
Copy-Item key.properties.example key.properties
```

Edit `key.properties` with the passwords entered in `keytool`. Both
`key.properties` and keystore files are ignored by Git and must be backed up in
a secure password manager or secrets vault.

## Build the Play Store bundle

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

The signed bundle is created under `build/app/outputs/bundle/release/` only
when a valid local `key.properties` file and keystore are present.
