# pfSense Manager

pfSense Manager is a Flutter Android app for managing multiple pfSense instances from a phone.

## Features

- Multiple pfSense profiles
- Dashboard and system status views
- Firewall rules and firewall logs
- DHCP leases
- Services and VPN screens
- Network monitoring
- Local lock screen and secure profile storage
- Light/dark theme support and localization plumbing

## Requirements

- Flutter SDK 3.2 or newer
- Android SDK
- JDK 17

## Build

```bash
flutter pub get
flutter build apk --release
```

The APK will be written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Signing

Release signing files are intentionally not committed.

For local signed builds, create `android/key.properties`:

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=app/pfsense-release.jks
```

Place the keystore at `android/app/pfsense-release.jks`.

For GitHub Actions releases, add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

Then push a version tag such as `v1.5.0`. The workflow will build a signed release APK, create a GitHub Release, and upload the APK plus checksum.

## Current Release

Version: `1.5.0+7`

APK checksum:

```text
5c5e6df3c921dc34933a73383913d001dc9feacdb46d7a0054587061dcc9e9b1
```
