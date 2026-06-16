# pfSense Manager 1.7.4

Version `1.7.4+13` is a maintenance and usability release focused on clearer monitoring, more reliable pfSense Plus system details, and controllable Dashboard warnings.

## Highlights

- Settings retains direct access to the five primary app destinations.
- CPU and per-core temperature sensors are displayed separately.
- Fahrenheit helper values are filtered so they cannot produce false Celsius alerts such as `113.4 °C`.
- System Information now handles nested pfSense Plus response fields and additional firmware, architecture, hostname, platform, kernel, and uptime aliases.
- Router firmware and the installed pfSense Manager app version are displayed separately.
- Numeric uptime values are converted to readable days, hours, and minutes.
- Dashboard warning chips open detailed explanations and recommended checks.
- Warnings can be ignored per firewall profile or snoozed for 24 hours.
- Ignored warnings can be restored from Settings.
- Temporary repository marker and note files have been removed.

## Release verification

The production workflow checks that the APK reports:

- Application ID: `com.privacyog.pfsense_manager`
- Version name: `1.7.4`
- Version code: `13`

It also runs the Flutter tests, builds the production APK with the configured Android release keystore, verifies the APK signature with `apksigner`, and publishes a SHA-256 checksum beside the APK.

## Upgrade notes

Users already running version 1.7.3 under the current Android application ID can install this release as a normal update, provided the APK is signed with the same release key.
