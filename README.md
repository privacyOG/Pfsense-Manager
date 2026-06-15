# pfSense Manager


❤️ Support the Project
If you find this project useful, consider supporting its development:

💰 Crypto Donations
Monero (XMR)
82oJ62ScSZLcVoLfJzAPz7NHZ25kMLaBDSZwScR6wjekeqWanZAfLcT9fnrFG31p3hGhWPG9GuXH1VNAoEbLbkw8RPXP2g8

<img width="651" height="649" alt="8753d4e0831845b046c66bf82177ea311ba7cedd6fc17505ae1dfe948708275a" src="https://github.com/user-attachments/assets/5b0f412f-042f-4d98-b1a7-044cf5b6902a" />

**About pfSemse Manager**

pfSense Manager is an Android app I am building to monitor and manage pfSense firewalls from a phone.

It is written in Flutter and connects to the pfSense REST API. Multiple firewall profiles can be saved, which is useful when looking after more than one pfSense installation.

The project is still under development. Check the release notes before using it against an important or production firewall.

## What it currently supports

- Multiple pfSense profiles
- System, interface and gateway status
- Firewall rule viewing and management
- Firewall logs
- Current firewall states
- DHCP lease viewing
- Starting, stopping and restarting services
- OpenVPN status
- Restarting OpenVPN
- Rebooting pfSense
- Local app lock
- Encrypted storage for profile credentials
- Light and dark themes

## pfSense requirements

The app uses the pfSense REST API v2 endpoints. The normal pfSense web interface by itself is not enough.

Before adding a firewall to the app:

1. Install and enable the pfSense REST API package.
2. Create an API key with only the permissions you need.
3. Make sure the API is available over HTTPS.
4. Confirm that the phone can reach the pfSense address, either locally or through a VPN.

The app deliberately rejects plain HTTP connections.

Self-signed certificates can be allowed for a profile, but doing this disables normal certificate verification for that connection. A certificate issued by a trusted internal CA is preferable.

## Building the app

You will need:

- Flutter with Dart 3.2 or newer
- Android SDK
- JDK 17

Clone the repository and run:

```bash
flutter pub get
flutter build apk --release
```

The release APK will be created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Release signing

Signing keys and passwords are not stored in this repository.

For a locally signed build, create `android/key.properties`:

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=app/pfsense-release.jks
```

Place the keystore at:

```text
android/app/pfsense-release.jks
```

The GitHub Actions release workflow expects these repository secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_PASSWORD
ANDROID_KEY_ALIAS
```

Pushing a version tag such as `v1.5.0` builds the signed APK and attaches it, together with its SHA-256 checksum, to a GitHub release.

## Security notes

This app can perform administrative actions on a firewall. Use a dedicated API account or key with restricted permissions rather than unrestricted administrator credentials.

Do not expose the pfSense REST API directly to the public internet. Access it from a trusted network or through a VPN.

Credentials are stored using Android secure storage, but users should still protect the device with a strong screen lock.

## Current version

`1.5.0+7`

Release APKs and checksums are available from the repository's Releases page.

## Status

This is an independent project and is not affiliated with or endorsed by Netgate.
