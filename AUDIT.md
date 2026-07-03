# pfSense Manager — Code & UX Audit (July 2026)

Scope: full review of the Flutter app source (`lib/`, 78 files, ~19.5k lines), the git
history and repository metadata, static analysis (`flutter analyze`, Flutter 3.44.2),
the full test suite (77 tests, all passing), and a cross-check of every REST endpoint
the app calls against the official pfSense REST API (pfrest) v2 package source.

---

## 1. Repository hygiene — authorship and labels

- All 90+ commits are authored and committed as `privacyOG <kriptiik@proton.me>`
  (plus GitHub's web-flow committer on merges). No foreign author identities.
- CI signs release commits as `github-actions[bot]`, which is standard GitHub
  automation.
- The `.gitignore` comment above the `.claude/` entry has been reworded to a neutral
  "Local tooling state" label (this change is included on this branch).
- Two **historical commits on `main`** still carry tool references inside their commit
  messages. Cleaning these requires a history rewrite and force-push of `main`, which
  invalidates existing clones and release tags, so it is left as a deliberate owner
  decision rather than done here:
  - `e89bfb2` ("Flutter UI upgrades: Material You, home widget, tablet layout,
    interactive charts") — contains a `Co-authored-by` trailer pointing at an
    AI tool identity in the message body.
  - `005345e` ("chore: ignore .claude agent state directory") — the message itself
    names the tool directory.

  If a rewrite is wanted, `git filter-repo --message-callback` (dropping the trailer
  and rewording the second message) followed by a coordinated force-push is the
  cleanest route. Alternatively, both messages disappear from casual view once the
  repository squashes history at the next major release.

---

## 2. Broken or buggy behaviour found

### High impact

1. **Gateway history is unreachable (dead feature).**
   `HomeScreen`, `GatewayHistoryScreen` and `SystemInfoScreen` are orphaned: nothing
   navigates to them. The app shell (`HomeShell`) replaced `HomeScreen`, but the
   latency/packet-loss history charts (a README headline feature, fully implemented
   and covered by tests in `gateway_history_panel_test.dart`) were left behind. The
   richer firmware/repository detail view (`SystemInfoDetails`) is stranded the same
   way, along with the unused `NetworkAssetText` widget.
   *Fix: add "Gateway history" to the More section or as a tab under Network, and
   fold `SystemInfoDetails` into the System tab; otherwise delete the dead files.*

2. **Hardware Health screen fails entirely on a stock pfrest install.**
   `_load()` runs `Future.wait([getHardwareHealth(), getSmartStatus()])`. The SMART
   endpoint (`/api/v2/diagnostics/smart_status`) does not exist in the official
   pfrest package, so the whole future fails and the screen shows only an error —
   thermal sensors and memory/swap trends never render, even though that data was
   fetched successfully. *Fix: fetch SMART separately and degrade gracefully.*

3. **Firewall rule form can silently move a rule to WAN.**
   The interface dropdown is hardcoded to `['wan', 'lan', 'opt1', 'opt2']`. Editing a
   rule that lives on any other interface (opt3+, VLANs, interface groups) makes the
   dropdown fall back to `wan`; saving then rewrites the rule's interface. *Fix:
   populate the dropdown from `/api/v2/status/interfaces` (already fetched elsewhere)
   and always include the rule's current interface.*

4. **Protocol "any" is rejected by the API.**
   `FirewallRule.toJson()` always sends `protocol`, and sends the literal string
   `any` when unset. pfrest's `FirewallRule` model only accepts
   `tcp/udp/tcp\-udp/icmp/esp/ah/gre/ipv6/igmp/pim/ospf/carp/pfsync` — "any" is
   expressed by *omitting* the field. Creating a rule with protocol "any" (a form
   option), or re-saving a rule that has no protocol set, returns a validation error.
   *Fix: drop the `protocol` key when it is `any`/empty.*

5. **Several visible features target endpoints that do not exist in official pfrest v2**
   (verified against the package source). They are feature-guarded so they degrade to
   "not supported" messages, but they are presented as first-class features:
   - Remote Diagnostics → Traceroute and DNS Lookup tabs (`/diagnostics/traceroute`,
     `/diagnostics/dns_lookup`). Ping is real and works.
   - Captive Portal screen (sessions, vouchers) — no captive portal endpoints exist.
   - pfBlockerNG screen (`/status/pfblockerng`) — no pfBlockerNG endpoints exist.
   - More → Configuration backup (`/api/v2/system/config`) — endpoint absent; the
     download is also written with an `.xml` extension although the API (if it
     existed) would return JSON.

   *Fix options: remove/hide these until server-side support exists, gate them behind
   a capability probe at connect time, or implement the backup via
   `/api/v2/diagnostics/config_history` revisions (which does exist).*

### Medium impact

6. **Home-screen widget never shows traffic rates.** The dashboard pushes
   `trafficIn: null, trafficOut: null` on every refresh, so the widget's traffic slots
   permanently display `--` even though the network monitor computes exactly these
   rates. The widget also reports the *first* thermal sensor rather than the hottest
   one, unlike the dashboard.

7. **Pollers that never sleep.** Top Talkers re-polls every 10 s and Hardware Health
   every 30 s with no app-lifecycle or live/pause gate (Dashboard, Network monitor and
   Gateway history all have one). With the app backgrounded, both keep hitting the
   firewall and draining battery until Android kills the process.

8. **NOC wallboard is a frozen snapshot.** It renders the `DashboardData` captured at
   the moment it was opened and never refreshes — the opposite of what a wallboard is
   for. It should subscribe to the same refresh loop (and ideally keep the screen on).

9. **Language switching only half works.** `lib/l10n/app_localizations.dart` is a
   hardcoded English stub that is not registered in `MaterialApp.localizationsDelegates`
   (its `of()` always returns English), while `AppStrings` is the real localized system
   (EN/AR/ES/FR/DE). Screens are split between the two, and many screens use raw
   English literals besides. Selecting Arabic/Spanish/French/German translates some
   screens (VPN, DHCP, Top Talkers) and leaves others (Dashboard, Firewall form,
   Settings, Diagnostics, Captive Portal) in English.

10. **pfBlockerNG "not available" card is dead code.** `getPfBlockerStatus()` throws
    `UnsupportedApiFeatureException` for missing endpoints; it never returns null, so
    `_available` never becomes false and users see a raw error card instead of the
    designed friendly "package not available" state.

### Low impact / polish

11. **No way to delete a firewall rule** from the UI even though
    `PfSenseService.deleteFirewallRule()` is implemented and the API supports it.
12. **Gateway history chart:** `_touchedIndex` is written but never read (the one
    `flutter analyze` warning), and `GatewayHistorySection.didUpdateWidget` records a
    new sample on *any* parent rebuild (e.g. toggling the Live chip), not only when new
    data arrives — duplicate samples slightly distort the time axis.
13. **Network monitor list performance.** Up to 250 state cards are rebuilt inside a
    non-builder `ListView` every 1–3 s poll; on large state tables this causes jank.
    A `ListView.builder`/sliver structure would rebuild only visible tiles.
14. **PIN setup has no confirmation field** and no digit-only input formatter — a
    mistyped PIN locks the user out until they clear app data.
15. **Settings screen shows a phone-style bottom navigation bar even on tablets**
    where the main shell uses a navigation rail.
16. Analyzer infos worth clearing: deprecated `DropdownButtonFormField.value` →
    `initialValue` (dhcp_leases_screen), deprecated `Color.value` (settings_screen),
    deprecated `isInDebugMode` (workmanager in alert_service), a few `prefer_const`.

Not bugs, but verified good: request de-duplication and generation-checking across
screens is consistent and correct; HTTPS is enforced; API keys live only in encrypted
storage and are stripped from exported profiles; DHCP lease delete, Wake-on-LAN
payloads, service actions and the firewall apply-after-write flow all match the
pfrest models; ping payload (`host`/`count`/`source_address`) matches; redirects are
refused (protects the API key); reboot/stop/restart actions are protected by
slide-to-confirm.

---

## 3. Suggested UI/UX upgrades

- **Restore lost features:** Gateway history charts and the detailed system info view
  (finding 1) are finished work — a navigation entry each is all that's missing.
- **Live NOC mode:** refresh the wallboard on the dashboard interval, add
  keep-screen-on, and a tap-to-cycle layout for wall mounting.
- **Rule management:** swipe-to-delete / long-press context menu on firewall rules;
  show a per-rule hit counter (states) where available; a read-only "advanced" section
  for fields the form doesn't cover instead of dropping them on save.
- **Capability-aware navigation:** probe supported endpoints once per connection and
  hide or badge unsupported sections ("requires pfrest x.y / package not installed")
  instead of showing error cards after a tap.
- **Widget parity:** feed real throughput into the home-screen widget and use the
  hottest sensor; add a tap action that deep-links to the matching screen.
- **Search:** the spotlight search swallows load errors and shows "no results" —
  surface a retry row; make the detail sheet scrollable for long rule detail lists.
- **Unify localization** on `AppStrings`, delete the English stub, and move the
  remaining hardcoded literals into it; RTL review for the Arabic locale.
- **Theme consistency:** dashboard gauges, gateway/interface cards and both chart
  palettes still use fixed hex colours (`0xFF00C2A8`, `0xFF5E9CFF`, …) that ignore the
  accent picker and AMOLED accent — map them to `ColorScheme` roles or a small
  semantic palette derived from the theme.
- **Lists at scale:** builder-based lists for firewall states/logs/DHCP leases;
  sticky section headers; pull filtering server-side via pfrest query parameters
  (plural endpoints support field filters, `limit`, `offset`, `sort_by`).
- **PIN flow:** confirmation field, digits-only formatter, and an option to unlock
  with biometrics alone.

---

## 4. Feature opportunities available today via pfrest v2

All of the following are confirmed present in the official package and currently
unused by the app:

**Firewall**
- Aliases CRUD (`/firewall/alias[es]`) — the single biggest quality-of-life add;
  rules referencing aliases could resolve chips inline.
- NAT: port forwards, outbound mappings and outbound mode.
- Virtual IPs, rule schedules, traffic shaper + limiters.
- Individual state kill (`DELETE /firewall/state`) and states size — a "kill
  connection" action on the Network monitor tiles.

**Diagnostics & system**
- ARP table with delete (`/diagnostics/arp_table`) — natural companion to DHCP leases.
- Config history revisions (`/diagnostics/config_history/revisions`) — a working
  backup/restore-point browser to replace the non-functional backup card.
- Halt system (shutdown, not just reboot).
- `/system/version` — "update available" indicator on the dashboard.
- Packages (list/install/remove), certificates + CRLs (with expiry warnings),
  tunables, REST API settings/version.

**Services**
- DNS Resolver host overrides + apply — a local DNS records manager screen.
- DHCP server config + static mappings — a "promote lease to static mapping" button
  on the DHCP screen would be a standout feature.
- Cron jobs, NTP, SSH settings, Service Watchdog, HAProxy, BIND, ACME certificate
  issuance/renewal.

**VPN & HA**
- Full WireGuard CRUD (tunnels/peers + apply) instead of read-only status.
- OpenVPN server/client config management; IPsec phase 1/2 with apply.
- CARP status (`/status/carp`) — HA failover visibility.

**Platform**
- Users and groups management.
- GraphQL endpoint — batch dashboard queries into a single request per tick.
- JWT auth (`/auth/jwt`) — the client already has `getJwtToken()`; offering
  username/password login with short-lived tokens would avoid storing long-lived
  API keys on devices.

---

## 5. Verification

- `flutter analyze`: 11 findings (1 warning, 10 infos) — detailed in section 2.
- `flutter test`: 77/77 passing.
- Endpoint existence: checked each path the app calls against the pfrest package
  endpoint classes; model field names (`Ping`, `WakeOnLANSend`, `DHCPServerLease`,
  `FirewallRule`) cross-checked against the app's payloads.
