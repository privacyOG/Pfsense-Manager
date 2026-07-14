# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.0] - 2026-07-14

Maintained by PrivacyOG.

### Added

- **Capability-aware pfREST architecture** — the app now discovers available endpoints, methods, fields, permissions, read-only values and write-only secrets from the connected firewall's OpenAPI schema before exposing management operations.
- **Firewall and network management** — firewall aliases, NAT rules, the expanded pfREST firewall-rule model, interface configuration, gateways, gateway groups and static routes can now be managed with local validation and dependency-aware destructive actions.
- **DHCP management** — per-interface DHCP settings, primary and additional pools, static mappings, relay configuration, backend selection and lease-to-static conversion are available when reported by pfREST.
- **DNS services management** — DNS Resolver settings, forwarding, DNSSEC, host and domain overrides, access lists, aliases, child networks and supported DNS Forwarder host overrides can now be managed.
- **VPN configuration management** — OpenVPN servers, clients, client-specific overrides and export defaults; IPsec Phase 1 and Phase 2 entries; and WireGuard settings, tunnels, peers, addresses and allowed IPs can now be managed independently.
- **Administrative system management** — certificate authorities, certificates, revocation lists and revoked certificates; local users, groups and authentication servers; REST API keys and access controls; system tunables, packages, system updates; and reported NTP, SSH, SNMP and remote-logging settings are available from a dedicated administration workspace.
- **Stock diagnostics and recovery** — ARP entries, pf tables, configuration-history revisions, system halt, expanded service logs and a separately unlocked command console are available when the connected schema and profile permissions allow them.
- **Permission-aware read-only operation** — users with restricted profiles can continue to view supported non-mutating resources while unavailable writes remain hidden or disabled.

### Changed

- **Network Activity and navigation** were refined for more compact monitoring, stable interface ordering and clearer Network-tab and bottom-navigation selection.
- **Authentication and session handling** now separate JWT password profiles from API-key profiles, preserve permission and connectivity failures, close superseded resources and prevent stale responses from replacing newer sessions.
- **Dashboard and background monitoring** tolerate partial pfREST responses, expose alert diagnostics and use deterministic background-notification identifiers.
- **Secret handling** uses blank replacement-only fields, recursively removes credentials and private material from managed records, and displays generated secrets or certificate material only as one-time results.
- **Destructive operations** use explicit slide confirmation for firewall-impacting changes, VPN relationships, certificate and identity changes, package and system actions, ARP or pf-table deletion, configuration recovery, reboot, halt and command execution.
- **OpenVPN service control** starts, stops and restarts the exact reported service instance rather than acting on a generic VPN service.
- **System-log discovery** now maps stock DHCP, Services, Authentication, OpenVPN and REST API log aliases from OpenAPI while clearly labelling non-standard DNS and gateway extensions.
- **Release metadata validation** keeps `pubspec.yaml`, `CHANGELOG.md`, README release guidance and Android signing instructions consistent in pull-request and signed-release workflows.

### Fixed

- Firewall rule interface filtering, unrestricted protocol serialization, IP protocol preservation and destination-port range validation now match the pfREST model.
- Firewall log filtering now uses the reported pfREST log structure.
- Ping packet counts remain within the pfREST-supported limit.
- IPv6 profile endpoints are parsed correctly.
- Request-cache cleanup no longer produces unobserved errors.
- Health checks no longer replace useful connection or permission failures with generic errors.
- System repository metadata is no longer fabricated when pfREST does not report it.
- VPN dependency checks resolve IPsec `ikeid`, WireGuard tunnel names and OpenVPN `vpnid` values before parent deletion.
- WireGuard settings validate the active endpoint-resolution interval.
- Configuration-history XML, command output, saved credentials, API-key headers, JWTs and private-key blocks are removed or redacted before display.

**Upgrade note:** Users running version 1.8.2 can install version 1.9.0 as a normal update when the APK is signed with the same release key.

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