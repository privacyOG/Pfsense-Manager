<p align="center">
  <img src="assets/readme/app_icon.svg" width="250" height="250" alt="pfSense Manager app icon" />
</p>

<h1 align="center">pfSense Manager</h1>

<div align="center">

### ❤️ Support the Project

If you find this project useful, consider supporting its continued development.

**Monero (XMR)**

```text
82oJ62ScSZLcVoLfJzAPz7NHZ25kMLaBDSZwScR6wjekeqWanZAfLcT9fnrFG31p3hGhWPG9GuXH1VNAoEbLbkw8RPXP2g8
```

<img width="250" height="250" alt="Monero donation QR code" src="https://github.com/user-attachments/assets/5b0f412f-042f-4d98-b1a7-044cf5b6902a" />

</div>

## About pfSense Manager

pfSense Manager is an Android app for monitoring and managing pfSense firewalls from a phone.

It is written in Flutter and connects to the pfSense REST API. Multiple firewall profiles can be saved, which is useful when looking after more than one pfSense installation.

The project is still under development. Check the release notes before using it against an important or production firewall.

## What it currently supports

- Multiple pfSense profiles
- System, interface and gateway status
- Expanded firmware, repository and platform details
- Live gateway latency and packet-loss history
- Saved live/pause and gateway refresh intervals
- CPU and per-core thermal sensor monitoring
- Real-time network throughput charts
- Per-interface byte, packet, error and collision counters
- Reorderable, persistent Dashboard sections
- Clickable Dashboard warning details and recommended checks
- Per-profile warning ignore and 24-hour snooze controls
- Settings controls for restoring ignored warnings
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
storeFile=pfsense-release.jks
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

Pushing the tag matching the application version, in the form `v<major>.<minor>.<patch>`, builds the signed APK and attaches it, together with its SHA-256 checksum, to a GitHub release.

## Security notes

This app can perform administrative actions on a firewall. Use a dedicated API account or key with restricted permissions rather than unrestricted administrator credentials.

Do not expose the pfSense REST API directly to the public internet. Access it from a trusted network or through a VPN.

Credentials are stored using Android secure storage, but users should still protect the device with a strong screen lock.

## Legal and privacy

- [GNU General Public License v3.0](LICENSE)
- [Project notice](NOTICE)
- [Privacy policy](PRIVACY_POLICY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

pfSense Manager is licensed under **GPL-3.0-only**. Distributed modified versions must remain available under GPLv3 with corresponding source code.

## Release metadata

The canonical application version is the `version:` field in `pubspec.yaml`.

The matching section in `CHANGELOG.md` supplies the release notes. Release APKs and checksums are available from the repository's Releases page.

## Status

This is an independent project and is not affiliated with or endorsed by Netgate.
