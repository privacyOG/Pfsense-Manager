# Changelog

## 1.7.4

- Added direct Settings navigation back to the five primary app destinations.
- Improved CPU temperature reporting by listing CPU and core sensors separately.
- Filtered Fahrenheit helper values so they are not misreported as Celsius alerts.
- Fixed nested pfSense Plus System Information parsing and expanded field aliases.
- Displayed router firmware and the installed pfSense Manager app version separately.
- Added numeric uptime formatting and default package mirror and repository information.
- Made Dashboard warning chips clickable with detailed explanations and recommended checks.
- Added per-profile Ignore warning and 24-hour Remind me later actions.
- Added a Settings control to restore ignored warnings.
- Removed temporary repository marker and documentation files.
- Improved production release automation with dynamic version metadata, APK identity checks, signing verification, and dedicated verification and release-trigger branches.

## 1.7.3

- Added live per-interface byte, packet, input error, output error, and collision counters.
- Added support for every reported CPU thermal sensor with hottest-sensor alerts.
- Added a dedicated Gateways screen with live latency and packet-loss history charts.
- Added saved live/pause controls and 1, 3, 5, or 10-second gateway refresh intervals.
- Added persistent Dashboard section ordering, visibility controls, long-press access, and layout reset.
- Expanded System Information with firmware, architecture, commit hash, package mirror, repository priorities, hostname, platform, uptime, and update timestamps.
- Improved README branding, donation details, supported-feature documentation, and version information.
- Added GNU GPLv3 licensing, project notices, a privacy policy, and third-party notices.
- Preserved session-safe polling, stale-response protection, lifecycle handling, and saved settings.

## 1.7.2

- Improved Network Monitor traffic graph readability.
- Added adaptive bandwidth scaling for changing traffic levels.
- Added a persisted display-unit selector for bits/s and Bytes/s.
- Improved bandwidth-axis labels, time labels, legends, fills, and tooltips.

## 1.7.0

- Improved navigation and screen state handling.
- Added safer request deduplication and stale-session protection.
- Improved Firewall Logs, Services, VPN, System, Dashboard, and Network Monitor reliability.
- Added persistent Network Monitor settings, including the 1-second refresh option.
- Added shared state-message components and migrated DHCP leases and Services.
- Renamed the Android package to `com.privacyog.pfsense_manager`.
- Added broader widget and lifecycle test coverage.

### Installation note

Because the Android application ID changed in this release, installations using the previous package ID must be uninstalled once before installing version 1.7.0. Future releases using the new package ID can update normally.
