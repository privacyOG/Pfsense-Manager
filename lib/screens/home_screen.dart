import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import 'dashboard_screen.dart';
import 'firewall_logs_screen.dart';
import 'firewall_rules_screen.dart';
import 'profiles_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'system_info_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = context.watch<ProfileProvider>();
    final session = context.watch<PfSenseSessionProvider>();
    final pages = const [DashboardScreen(), FirewallRulesScreen(), FirewallLogsScreen(), ServicesScreen(), SystemInfoScreen()];
    return Scaffold(
      appBar: AppBar(title: Text(l10n?.appTitle ?? 'pfSense Manager'), actions: [
        IconButton(icon: const Icon(Icons.dns_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilesScreen()))),
        IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: profiles.profiles.isEmpty
            ? FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilesScreen())), icon: const Icon(Icons.add), label: Text(l10n?.addProfile ?? 'Add profile'))
            : DropdownButtonFormField<String>(
                value: profiles.selectedProfileId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n?.profiles ?? 'Profiles', prefixIcon: const Icon(Icons.router_outlined)),
                items: [for (final profile in profiles.profiles) DropdownMenuItem(value: profile.id, child: Text(profile.name))],
                onChanged: (id) async {
                  if (id == null) return;
                  profiles.selectProfile(id);
                  final profile = profiles.selectedProfile;
                  if (profile == null) return;
                  await context.read<PfSenseSessionProvider>().connect(profile);
                  if (!mounted) return;
                  final current = context.read<PfSenseSessionProvider>();
                  if (!current.connected) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(current.connectionError ?? (l10n?.connectionFailed ?? 'Connection failed'))));
                },
              )),
        if (session.connectionError != null) MaterialBanner(content: Text(session.connectionError!), actions: [TextButton(onPressed: context.read<PfSenseSessionProvider>().clearError, child: Text(l10n?.cancel ?? 'Dismiss'))]),
        Expanded(child: pages[_index]),
      ])),
      bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (value) => setState(() => _index = value), destinations: [
        NavigationDestination(icon: const Icon(Icons.space_dashboard_outlined), label: l10n?.dashboard ?? 'Dashboard'),
        NavigationDestination(icon: const Icon(Icons.security_outlined), label: l10n?.firewallRules ?? 'Rules'),
        NavigationDestination(icon: const Icon(Icons.article_outlined), label: l10n?.logs ?? 'Logs'),
        NavigationDestination(icon: const Icon(Icons.miscellaneous_services_outlined), label: l10n?.services ?? 'Services'),
        NavigationDestination(icon: const Icon(Icons.info_outline), label: l10n?.systemInfo ?? 'System'),
      ]),
    );
  }
}
