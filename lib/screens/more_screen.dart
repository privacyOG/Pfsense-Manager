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
  bool _backingUp = false;

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        const _SectionHeading(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Management',
          subtitle: 'Core firewall services and application setup',
        ),
        _SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.miscellaneous_services_outlined),
              title: const Text('Services'),
              subtitle: const Text('Review and control pfSense services'),
              trailing: const Icon(Icons.chevron_right),
              onTap: session.connected
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ServicesScreen(),
                        ),
                      )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('System'),
              subtitle: const Text('Firmware, packages and system details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: session.connected
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SystemScreen(),
                        ),
                      )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Firewall profiles'),
              subtitle: const Text('Add, edit, import or test connections'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilesScreen()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Background alerts'),
              subtitle: const Text(
                'Gateway, packet-loss and temperature notifications',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AlertSettingsScreen(),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Settings'),
              subtitle: const Text('Appearance, language and app security'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeading(
          icon: Icons.build_outlined,
          title: 'Operations',
          subtitle: 'Diagnostics, backups and optional packages',
        ),
        _SectionCard(
          children: [
            PfRestFeatureListTile(
              decision: pfBlocker,
              enabled: session.connected,
              icon: Icons.security_outlined,
              title: 'pfBlockerNG',
              availableSubtitle: 'DNSBL stats, blocklist updates and controls',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PfBlockerFeatureScreen(),
                ),
              ),
            ),
            const Divider(height: 1),
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Hardware health'),
              subtitle: Text(
                smart.isAvailable
                    ? 'CPU temperatures, SMART drive status and memory trends'
                    : smart.isUnsupported
                        ? 'CPU temperatures and memory trends; SMART requires a custom extension'
                        : 'CPU temperatures and memory trends; SMART availability is unknown',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: session.connected
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HardwareHealthScreen(),
                        ),
                      )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.subject_outlined),
              title: const Text('System logs'),
              subtitle: const Text(
                'Log sources reported by the connected pfREST schema',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: session.connected
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SystemLogsScreen(),
                        ),
                      )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.network_ping_outlined),
              title: const Text('Remote diagnostics'),
              subtitle: Text(
                traceroute.isUnsupported && dnsLookup.isUnsupported
                    ? 'Ping is available; traceroute and DNS require custom extensions'
                    : 'Ping plus capability-aware traceroute and DNS lookup',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: session.connected
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      )
                  : null,
            ),
            const Divider(height: 1),
            PfRestFeatureListTile(
              decision: captiveEntry,
              enabled: session.connected,
              icon: Icons.wifi_password_outlined,
              title: 'Captive portal',
              availableSubtitle: 'Manage supported guest sessions and vouchers',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CaptivePortalFeatureScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
