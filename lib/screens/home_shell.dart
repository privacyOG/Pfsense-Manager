import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/brand_mark.dart';
import 'dashboard_screen.dart';
import 'dhcp_leases_screen.dart';
import 'firewall_logs_screen.dart';
import 'firewall_rules_screen.dart';
import 'network_monitor_screen.dart';
import 'profiles_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'system_screen.dart';
import 'vpn_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = [
      _NavItem(strings.t('dashboard'), Icons.monitor_heart_outlined,
          Icons.monitor_heart, const DashboardScreen()),
      const _NavItem('Firewall', Icons.shield_outlined, Icons.shield,
          FirewallRulesScreen()),
      const _NavItem('Firewall Logs', Icons.receipt_long_outlined,
          Icons.receipt_long, FirewallLogsScreen()),
      const _NavItem('Live Network', Icons.radar_outlined, Icons.radar,
          NetworkMonitorScreen()),
      const _NavItem('DHCP Leases', Icons.router_outlined, Icons.router,
          DhcpLeasesScreen()),
      _NavItem(strings.t('services'), Icons.miscellaneous_services_outlined,
          Icons.miscellaneous_services, const ServicesScreen()),
      _NavItem(strings.t('system'), Icons.info_outline, Icons.info,
          const SystemScreen()),
      _NavItem(strings.t('vpn'), Icons.vpn_key_outlined, Icons.vpn_key,
          const VpnScreen()),
      _NavItem(strings.t('settings'), Icons.tune, Icons.tune,
          const SettingsScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(items[_index].label),
        actions: [
          IconButton(
            tooltip: strings.t('profiles'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfilesScreen())),
            icon: const Icon(Icons.storage),
          ),
          Consumer2<ProfileProvider, PfSenseSessionProvider>(
            builder: (context, profiles, session, _) {
              final selected = profiles.selectedProfile;
              return IconButton(
                tooltip: session.connected
                    ? strings.t('disconnect')
                    : strings.t('connect'),
                onPressed: selected == null
                    ? null
                    : () {
                        if (session.connected) {
                          session.disconnect();
                        } else {
                          session.connect(selected);
                        }
                      },
                icon: Icon(session.connected ? Icons.link_off : Icons.link),
              );
            },
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          Navigator.pop(context);
          setState(() => _index = value);
        },
        children: [
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                PfSenseBrandMark(size: 44, elevation: false),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'pfSense Manager',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          for (final item in items)
            NavigationDrawerDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: Text(item.label),
            ),
        ],
      ),
      body: Column(
        children: [
          const _ConnectionBanner(),
          Expanded(child: items[_index].screen),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index < 5 ? _index : 0,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (final item in items.take(5))
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer2<ProfileProvider, PfSenseSessionProvider>(
      builder: (context, profiles, session, _) {
        final profile = profiles.selectedProfile;
        final color = session.connected
            ? Colors.green
            : session.connectionError != null
                ? Colors.red
                : Colors.orange;
        final text = profile == null
            ? 'No profile selected'
            : session.connected
                ? '${profile.name} connected'
                : session.connectionError ?? '${profile.name} ready';
        return Material(
          color: color.withValues(alpha: 0.12),
          child: ListTile(
            dense: true,
            leading: Icon(Icons.circle, color: color, size: 14),
            title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: profile == null
                ? TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                    ),
                    child: const Text('Add'),
                  )
                : null,
          ),
        );
      },
    );
  }
}
