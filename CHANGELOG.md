# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

No notable changes yet.

## [1.7.4] - 2026-06-16

### Added

- Dashboard warning chips now open detailed explanations and recommended checks.
- Warnings can be ignored per firewall profile or snoozed for 24 hours.
- Ignored warnings can be restored from Settings.

### Changed

- Settings retains direct access to the five primary app destinations.
- CPU and per-core temperature sensors are displayed separately.
- System Information now handles nested pfSense Plus response fields and additional firmware, architecture, hostname, platform, kernel, and uptime aliases.
- Router firmware and the installed pfSense Manager app version are displayed separately.
- Numeric uptime values are converted to readable days, hours, and minutes.
- Production release automation now validates dynamic version metadata, APK identity, APK signatures, checksums, and an explicit reviewed release authorization.

### Fixed

- Fahrenheit helper values are filtered so they cannot produce false Celsius alerts such as `113.4 °C`.

### Removed

- Temporary repository marker and note files.

**Upgrade note:** Users already running version 1.7.3 under the current Android application ID can install this release as a normal update, provided the APK is signed with the same release key.

## [1.7.3] - 2026-06-16

### Added

- Live per-interface byte, packet, input-error, output-error, and collision counters.
- Support for every reported CPU thermal sensor with hottest-sensor alerts.
- A dedicated Gateways screen with live latency and packet-loss history charts.
- Saved live and pause controls with selectable 1, 3, 5, or 10-second gateway refresh intervals.
- Persistent Dashboard section ordering, visibility controls, long-press access, and layout reset.
- GNU GPLv3 licensing, project notices, a privacy policy, and third-party notices.

### Changed

- System Information was expanded with firmware, architecture, commit hash, package mirror, repository priorities, hostname, platform, uptime, and update timestamps.
- README branding, donation details, supported-feature documentation, and version information were improved.
- Session-safe polling, stale-response protection, lifecycle handling, and saved settings were preserved while monitoring features were expanded.

**Upgrade note:** Users running version 1.7.2 can install 1.7.3 as a normal update when the APK is signed with the same release key.

## [1.7.2] - 2026-06-15

### Added

- Adaptive bandwidth scaling for changing traffic levels.
- A persisted display-unit selector for bits/s and Bytes/s.
- Live byte, packet, error, and collision counters for every interface.
- All reported CPU thermal sensors on the Dashboard.
- A dedicated Gateways screen with live latency and packet-loss history charts.

### Changed

- Network Monitor traffic graph readability was improved.
- Bandwidth-axis labels, time labels, legends, fills, and tooltips were improved.
- Existing session, polling, lifecycle, and saved-setting protections were preserved.

**Upgrade note:** Users running version 1.7.1 can install 1.7.2 as a normal update when the APK is signed with the same release key.

## [1.7.0]

### Added

- Persistent Network Monitor settings, including the 1-second refresh option.
- Shared state-message components for DHCP leases and Services.
- Broader widget and lifecycle test coverage.

### Changed

- Navigation and screen-state handling were improved.
- Firewall Logs, Services, VPN, System, Dashboard, and Network Monitor reliability were improved.
- The Android package was renamed to `com.privacyog.pfsense_manager`.

### Fixed

- Request deduplication and stale-session protection were strengthened.

**Installation note:** Because the Android application ID changed in this release, installations using the previous package ID must be uninstalled once before installing version 1.7.0. Future releases using the new package ID can update normally.
