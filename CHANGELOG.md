# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Localization (Network screens)** — the DHCP leases and Top Talkers screens now route every user-facing string through the app's localization system with complete English, Arabic, Spanish, French, and German translations, instead of being hardcoded in English. A new `AppStrings.f(key, params)` helper supplies placeholder substitution for interpolated strings (timestamps, counts, device names). This is the first batch of a wider pass to localize the remaining feature screens.

### Fixed

- The application lock now protects cold launch and app resume, and active pfSense sessions remain suspended until PIN or device authentication succeeds.
- Application PINs are migrated from plaintext preferences to salted verification values in secure storage, with retry delays after repeated incorrect attempts.
- **Test connection** button on the firewall profiles screen always failed with an authentication error because it used the in-memory profile (which never holds an API key). It now resolves credentials from the secure keystore before dialling.
- **Profile import** count displayed as a raw object reference instead of a number due to a missing `await`. The correct count is now shown in the confirmation snackbar.
- **Firewall rules** with no explicit `disabled` field in the API response were incorrectly rendered as disabled. The parser now treats an absent key as enabled.
- **Network monitor screen** was painted entirely in hardcoded dark-navy hex values, making the screen unreadable in light mode. All colours now use Material Design 3 `colorScheme` tokens.
- **Settings navigation** now returns the user to the same tab they were on instead of tearing down and rebuilding the home shell and losing scroll position and loaded data.
- Stale async responses triggered by a profile switch or reconnection no longer overwrite the data currently on screen (pfBlockerNG screen was missing the generation guard that all other screens already had).
- WireGuard, S.M.A.R.T., and pfBlockerNG status errors that indicate network or authentication failures now propagate to the UI instead of being silently swallowed.
- Background alert service Dio instance now sets `followRedirects: false`, matching the main API client and preventing silent credential exposure on redirect.
- Replaced all remaining `Color.withOpacity()` calls with the non-deprecated `Color.withValues(alpha:)` equivalent.
- **Chart and counter-tile colours** in the gateway history panel, hardware health screen, network monitor screen, and interface traffic totals were hardcoded to dark-navy hex values. All are now resolved from the active Material Design 3 `colorScheme` so they render correctly in light mode and AMOLED themes.
- **Loading spinner in FilledButton** used hardcoded `Colors.white` for the `CircularProgressIndicator` colour. The AMOLED theme sets `onPrimary` to black, making the spinner invisible. Both the diagnostics run button and the captive-portal voucher generate button now derive the spinner colour from `colorScheme.onPrimary`.

## [1.8.0] - 2026-06-18

### Added

- **WireGuard VPN support** — tunnel and peer status alongside OpenVPN and Tailscale, with per-peer last-handshake timestamps and a restart button.
- **pfBlockerNG dashboard** — active/paused status banner, DNSBL and IP block counters, update blocklists action, and pause/resume blocking with confirmation.
- **Configuration backup and export** — downloads the pfSense XML config and opens the system share sheet so it can be saved to Files, emailed, or sent anywhere.
- **Wake-on-LAN** — magic packet button on every DHCP lease tile that has a MAC address.
- **Background alerts** — 15-minute periodic checks via WorkManager fire local notifications when a gateway goes offline, packet loss exceeds threshold, or a thermal sensor exceeds the configured CPU temperature limit. Configurable from More → Background alerts.
- **Hardware health screen** — CPU and per-core thermal sensors, S.M.A.R.T. drive status with expandable per-drive detail (temperature, power-on hours, reallocated and pending sector counts), and memory/swap trend charts that accumulate up to 30 in-session samples.
- **True AMOLED multi-theme** — pure `#000000` scaffold and app bar, `#0A0A0A` surface cards, and four selectable neon accent profiles: Matrix Green, Midnight Neon, Dracula Purple, and Inferno Red. Palette choice persists across restarts.
- **Top Talkers screen** — real-time bandwidth ranking by device under Network → Talkers, auto-refreshing every 10 seconds with relative progress bars and pull-to-refresh.
- **Remote diagnostics screen** — ping, traceroute, and DNS lookup executed from the pfSense box (not the phone), with configurable packet count, hop limit, and record type. Results are shown in a selectable monospace block with a copy button.
- **Global spotlight search** — search icon in the app bar opens a full-screen overlay that queries DHCP leases, firewall rules, and services in parallel and filters locally on every keystroke.
- **NetworkAssetText widget** — IP and MAC addresses render with a dotted underline indicating they are tappable. Tapping opens a sheet with copy-to-clipboard and PTR reverse-DNS lookup actions.
- **Captive portal management** — Sessions tab lists active guest connections with uptime and byte counters and a one-tap disconnect; Vouchers tab generates and shares time-limited access codes in batch.

### Changed

- AMOLED mode overrides the dark-mode toggle and theme palette picker in Settings while active.
- VPN tunnel restart confirmation replaced with slide-to-confirm gesture.

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
