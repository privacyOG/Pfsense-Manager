import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../widgets/pfrest_feature_gate.dart';
import 'alert_settings_screen.dart';
import 'diagnostics_screen.dart';
import 'hardware_health_screen.dart';
import 'pfrest_feature_routes.dart';
import 'profiles_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'system_logs_screen.dart';
import 'system_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _searchController = TextEditingController();
  bool _backingUp = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String title, String subtitle, [String keywords = '']) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '$title $subtitle $keywords'.toLowerCase().contains(query);
  }

  Future<void> _downloadBackup(PfRestFeatureDecision decision) async {
    if (_backingUp || !decision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a firewall first.')),
      );
      return;
    }

    setState(() => _backingUp = true);
    try {
      final bytes = await session.service!.getConfigBackup();
      if (!mounted) return;
      final directory = await getTemporaryDirectory();
      final profileName = session.selectedProfile?.name ?? 'pfsense';
      final safeName = profileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final now = DateTime.now();
      final timestamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final file = File(
        '${directory.path}/${safeName}_config_$timestamp.xml',
      );
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'pfSense config backup – $profileName',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pfRestFeatureRequestErrorMessage(
                PfRestFeature.configurationBackup,
                error,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final pfBlocker = registry.decision(PfRestFeature.pfBlockerStatus);
    final backup = registry.decision(PfRestFeature.configurationBackup);
    final smart = registry.decision(PfRestFeature.smartStatus);
    final traceroute = registry.decision(PfRestFeature.traceroute);
    final dnsLookup = registry.decision(PfRestFeature.dnsLookup);
    final captiveSessions =
        registry.decision(PfRestFeature.captivePortalSessions);
    final captiveVouchers =
        registry.decision(PfRestFeature.captivePortalVouchers);
    final captiveEntry = captiveSessions.canAttempt
        ? captiveSessions
        : captiveVouchers;

    final management = <Widget>[
      if (_matches('Services', 'Review and control pfSense services', 'restart'))
        _HubTile(
          icon: Icons.miscellaneous_services_outlined,
          title: 'Services',
          subtitle: 'Review and control pfSense services',
          enabled: session.connected,
          onTap: () => _open(const ServicesScreen()),
        ),
      if (_matches('System', 'Firmware, packages and system details', 'update'))
        _HubTile(
          icon: Icons.info_outline,
          title: 'System',
          subtitle: 'Firmware, packages and system details',
          enabled: session.connected,
          onTap: () => _open(const SystemScreen()),
        ),
      if (_matches('Firewall profiles', 'Add, edit, import or test connections'))
        _HubTile(
          icon: Icons.storage_outlined,
          title: 'Firewall profiles',
          subtitle: 'Add, edit, import or test connections',
          onTap: () => _open(const ProfilesScreen()),
        ),
      if (_matches('Background alerts', 'Gateway, packet-loss and temperature notifications'))
        _HubTile(
          icon: Icons.notifications_active_outlined,
          title: 'Background alerts',
          subtitle: 'Gateway, packet-loss and temperature notifications',
          onTap: () => _open(const AlertSettingsScreen()),
        ),
      if (_matches('Settings', 'Appearance, language and app security', 'theme pin biometric'))
        _HubTile(
          icon: Icons.tune,
          title: 'Settings',
          subtitle: 'Appearance, language and app security',
          onTap: () => _open(const SettingsScreen()),
        ),
    ];

    final operations = <Widget>[
      if (_matches('pfBlockerNG', 'DNSBL stats, blocklist updates and controls'))
        PfRestFeatureListTile(
          decision: pfBlocker,
          enabled: session.connected,
          icon: Icons.security_outlined,
          title: 'pfBlockerNG',
          availableSubtitle: 'DNSBL stats, blocklist updates and controls',
          onTap: () => _open(const PfBlockerFeatureScreen()),
        ),
      if (_matches('Configuration backup', 'Download the firewall XML configuration', 'export'))
        PfRestFeatureListTile(
          decision: backup,
          enabled: session.connected && !_backingUp,
          icon: Icons.backup_outlined,
          title: 'Configuration backup',
          availableSubtitle: 'Download the firewall XML configuration',
          trailing: _backingUp
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          onTap: () => _downloadBackup(backup),
        ),
      if (_matches('Hardware health', 'CPU temperatures, drive status and memory trends', 'smart thermal'))
        _HubTile(
          icon: Icons.monitor_heart_outlined,
          title: 'Hardware health',
          subtitle: smart.isAvailable
              ? 'CPU temperatures, SMART drive status and memory trends'
              : smart.isUnsupported
                  ? 'CPU temperatures and memory trends; SMART requires an extension'
                  : 'CPU temperatures and memory trends; SMART availability is unknown',
          enabled: session.connected,
          onTap: () => _open(const HardwareHealthScreen()),
        ),
      if (_matches('System logs', 'Inspect system and package log sources'))
        _HubTile(
          icon: Icons.subject_outlined,
          title: 'System logs',
          subtitle: 'Inspect system and package log sources',
          enabled: session.connected,
          onTap: () => _open(const SystemLogsScreen()),
        ),
      if (_matches('Remote diagnostics', 'Ping, traceroute and DNS lookup', 'network test'))
        _HubTile(
          icon: Icons.network_ping_outlined,
          title: 'Remote diagnostics',
          subtitle: traceroute.isUnsupported && dnsLookup.isUnsupported
              ? 'Ping is available; traceroute and DNS require extensions'
              : 'Ping plus capability-aware traceroute and DNS lookup',
          enabled: session.connected,
          onTap: () => _open(const DiagnosticsScreen()),
        ),
      if (_matches('Captive portal', 'Manage guest sessions and vouchers', 'wifi'))
        PfRestFeatureListTile(
          decision: captiveEntry,
          enabled: session.connected,
          icon: Icons.wifi_password_outlined,
          title: 'Captive portal',
          availableSubtitle: 'Manage supported guest sessions and vouchers',
          onTap: () => _open(const CaptivePortalFeatureScreen()),
        ),
    ];

    final noResults = management.isEmpty && operations.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _OperatorStatusCard(
          connected: session.connected,
          connecting: session.connecting,
          profileName: session.selectedProfile?.name,
          endpoint: session.selectedProfile?.baseUrl,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('operator-hub-search'),
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Find a tool or setting',
            hintText: 'Search profiles, logs, backup, diagnostics…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 22),
        if (management.isNotEmpty) ...[
          const _SectionHeading(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Manage',
            subtitle: 'Firewall services, profiles, alerts and application setup',
          ),
          _SectionCard(children: management),
          const SizedBox(height: 22),
        ],
        if (operations.isNotEmpty) ...[
          const _SectionHeading(
            icon: Icons.build_outlined,
            title: 'Operate and troubleshoot',
            subtitle: 'Diagnostics, backups, logs and optional packages',
          ),
          _SectionCard(children: operations),
        ],
        if (noResults)
          _EmptySearchState(
            query: _query,
            onClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
      ],
    );
  }
}

class _OperatorStatusCard extends StatelessWidget {
  const _OperatorStatusCard({
    required this.connected,
    required this.connecting,
    required this.profileName,
    required this.endpoint,
  });

  final bool connected;
  final bool connecting;
  final String? profileName;
  final String? endpoint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = profileName ?? 'No firewall selected';
    final status = connecting
        ? 'Connecting'
        : connected
            ? 'Connected'
            : 'Offline';
    final statusColor = connecting
        ? scheme.tertiary
        : connected
            ? scheme.primary
            : scheme.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: connecting
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      connected ? Icons.router : Icons.router_outlined,
                      color: statusColor,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (endpoint != null)
                    Text(
                      endpoint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: 'Firewall status: $status',
              child: Chip(
                avatar: Icon(
                  connected ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: statusColor,
                ),
                label: Text(status),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.search_off, size: 42),
            const SizedBox(height: 12),
            Text(
              'No tools match “$query”',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Try a feature name such as backup, logs, profiles or diagnostics.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              label: const Text('Clear search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final separated = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) separated.add(const Divider(height: 1));
      separated.add(children[index]);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: separated),
    );
  }
}
