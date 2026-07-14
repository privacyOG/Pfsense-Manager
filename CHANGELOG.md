# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Routing management** — gateways, monitoring addresses and thresholds, default gateways, gateway groups, trigger levels, and static routes can now be managed through capability-reported pfREST endpoints. Gateway status remains linked to configuration, destructive gateway changes check known dependencies, and routing changes are applied only after successful writes.

### Changed

- Release metadata validation now keeps `pubspec.yaml`, `CHANGELOG.md`, README release guidance, and Android signing instructions consistent in pull-request and signed-release workflows.

## [1.8.2] - 2026-06-29

Maintained by PrivacyOG.

### Changed

- **Network Monitor refresh load** — interface counters now refresh on the selected live interval while the heavier firewall state list refreshes on a slower schedule, reducing pfSense load and avoiding visible refresh flashes during routine background polling.
- **Top Talkers ranking** — local devices are now selected from configured interface subnets, IPv4 and IPv6 endpoints are handled safely, current traffic rate is used as the primary ranking signal, and cumulative traffic remains visible as a total.
- **VPN status reporting** — OpenVPN server status is parsed into dedicated status data, connected clients are counted from nested connection lists, and WireGuard status display avoids treating missing handshake metadata as a failed handshake.
- **Optional feature handling** — optional pfrest endpoints now return a clear unsupported-feature response when the installed API package does not expose SMART status, traceroute, DNS lookup, configuration backup, pfBlockerNG, or captive portal support.

### Fixed

- **Top Talkers counters** now read pfrest `bytes_total`, `packets_total`, and `expires_in` fields, with compatibility fallbacks for older counter shapes.
- **Interface cards** now stay in a stable WAN, LAN, and OPT-style order during live refreshes.
- **Firewall rule writes** now use the correct pfrest rule workflow, include `ipprotocol`, omit unsupported client-only fields, and apply firewall changes after create, update, toggle, and delete operations.
- **Wake-on-LAN** now sends requests to the pfrest send endpoint with the required `interface` and `mac_addr` fields and requires an interface before sending.
- **System logs** now map DHCP logs to the correct pfrest log name and display unsupported-source messages when a log endpoint is not available.
- **DHCP leases** now parse `active_status`, `online_status`, and `descr` fields correctly while preserving compatibility with older status field names.
- **Diagnostics and alerts** now map ping source addresses, service running state, gateway packet loss, and system temperature fields to the current pfrest payload names.

**Upgrade note:** Users running version 1.8.1 can install version 1.8.2 as a normal update when the APK is signed with the same release key.

## [1.8.1] - 2026-06-25

Maintained by PrivacyOG.

### Added

- System log viewer.

### Changed

- Localized network, VPN, and pfBlockerNG screens.

### Fixed

- App lock, profile import, firewall rule display, theme colours, settings navigation, stale response handling, background alert handling, and spotlight result actions.

**Upgrade note:** Users running version 1.8.0 can install version 1.8.1 as a normal update when the APK is signed with the same release key.

## [1.8.0] - 2026-06-18

### Added

- WireGuard VPN support, pfBlockerNG dashboard, configuration export, Wake-on-LAN, background alerts, hardware health, AMOLED themes, Top Talkers, remote diagnostics, spotlight search, network asset copy actions, and captive portal management.

### Changed

- AMOLED mode overrides conflicting theme controls while active.
- VPN tunnel restart confirmation replaced with slide-to-confirm gesture.

## [1.7.4] - 2026-06-16

### Added

- Dashboard warning details, ignored warnings, and warning restore controls.

### Changed

- Settings navigation, temperature display, System Information parsing, version display, uptime display, and release automation checks were improved.

### Fixed

- Fahrenheit helper values are filtered so they cannot produce false Celsius alerts.

### Removed

- Temporary repository marker and note files.

## [1.7.3] - 2026-06-16

### Added

- Interface counters, thermal sensor support, gateway history charts, saved refresh controls, dashboard layout persistence, project notices, and privacy documentation.

### Changed

- System Information, README branding, polling safety, lifecycle handling, and saved settings were improved.

## [1.7.2] - 2026-06-15

### Added

- Bandwidth scaling, display-unit selection, interface counters, thermal sensors, and gateway charts.

### Changed

- Network Monitor charts, labels, legends, fills, tooltips, and session-safe polling were improved.

## [1.7.0]

### Added

- Persistent Network Monitor settings, shared state-message components, and broader widget and lifecycle test coverage.

### Changed

- Navigation and screen reliability were improved.
- The Android package was renamed to `com.privacyog.pfsense_manager`.

### Fixed

- Request deduplication and stale-session protection were strengthened.

**Installation note:** Because the Android application ID changed in this release, installations using the previous package ID must be uninstalled once before installing version 1.7.0. Future releases using the new package ID can update normally.
