# Changelog

## 1.7.2

- Improved Network Monitor traffic graph readability.
- Added adaptive bandwidth scaling for changing traffic levels.
- Added a persisted display-unit selector for bits/s and Bytes/s.
- Improved bandwidth-axis labels, time labels, legends, fills, and tooltips.
- Replaced stale Network Monitor state totals with live per-interface byte and packet counters.
- Added Network Monitor visibility for input errors, output errors, and collisions.
- Added Dashboard support for every reported CPU thermal sensor, including hottest-sensor alerts.
- Added a dedicated Gateways screen with live latency and packet-loss history charts.
- Added saved live/pause and 1, 3, 5, or 10-second refresh controls for gateway monitoring.
- Added persistent Dashboard section ordering with drag handles, visibility controls, long-press access, and layout reset.
- Preserved session-safe polling, stale-response protection, lifecycle handling, and saved settings.

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
