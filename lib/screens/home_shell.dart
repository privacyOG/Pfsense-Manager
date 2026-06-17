import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/brand_mark.dart';
import 'dashboard_screen.dart';
import 'dhcp_leases_screen.dart';
import 'hardware_health_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _navigationIndexKey = 'home.selectedDestination';
  int _selectedIndex = 0;
  String? _lastSelectedProfileId;
  bool _profileSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSelectedDestination();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSelectedDestination() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = preferences.getInt(_navigationIndexKey) ?? 0;
    final safeIndex = saved < 0 ? 0 : (saved > 4 ? 4 : saved);
    setState(() => _selectedIndex = safeIndex);
  }

  Future<void> _setSelectedDestination(int value) async {
    if (value == _selectedIndex) return;
    setState(() => _selectedIndex = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_navigationIndexKey, value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final profile = context.read<ProfileProvider>().selectedProfile;
    final session = context.read<PfSenseSessionProvider>();
    if (profile != null && !session.connected && !session.connecting) {
      session.reconnect(profile);
    }
  }

  void _scheduleProfileSync(PfSenseProfile? profile) {
    final profileId = profile?.id;
    if (profileId == _lastSelectedProfileId) return;
    _lastSelectedProfileId = profileId;
    if (_profileSyncScheduled) return;

    _profileSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _profileSyncScheduled = false;
      if (!mounted) return;

      final selected = context.read<ProfileProvider>().selectedProfile;
      final session = context.read<PfSenseSessionProvider>();
      if (selected == null) {
        if (session.selectedProfile != null ||
            session.connected ||
            session.connecting) {
          await session.disconnect(keepProfile: false);
        }
        return;
      }

      if (session.selectedProfile?.id == selected.id &&
          (session.connected || session.connecting)) {
        return;
      }
      await session.connect(selected);
    });
  }

  Future<void> _selectProfile(PfSenseProfile profile) async {
    final profiles = context.read<ProfileProvider>();
    final session = context.read<PfSenseSessionProvider>();

    _lastSelectedProfileId = profile.id;
    await profiles.selectProfile(profile.id);
    if (!mounted) return;
    await session.connect(profile);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final profiles = context.watch<ProfileProvider>();
    final selectedProfile = profiles.selectedProfile;
    _scheduleProfileSync(selectedProfile);

    final destinations = <_PrimaryDestination>[
      _PrimaryDestination(
        label: strings.t('dashboard'),
        icon: Icons.monitor_heart_outlined,
        selectedIcon: Icons.monitor_heart,
        child: const DashboardScreen(),
      ),
      const _PrimaryDestination(
        label: 'Firewall',
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield,
        child: _TabbedSection(
          tabs: [
            _SectionTab('Rules', Icons.rule_outlined, FirewallRulesScreen()),
            _SectionTab(
              'Logs',
              Icons.receipt_long_outlined,
              FirewallLogsScreen(),
            ),
          ],
        ),
      ),
      const _PrimaryDestination(
        label: 'Network',
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub,
        child: _TabbedSection(
          tabs: [
            _SectionTab('Live', Icons.radar_outlined, NetworkMonitorScreen()),
            _SectionTab('DHCP', Icons.router_outlined, DhcpLeasesScreen()),
          ],
        ),
      ),
      _PrimaryDestination(
        label: strings.t('services'),
        icon: Icons.miscellaneous_services_outlined,
        selectedIcon: Icons.miscellaneous_services,
        child: _TabbedSection(
          tabs: [
            _SectionTab(
              strings.t('services'),
              Icons.miscellaneous_services_outlined,
              const ServicesScreen(),
            ),
            _SectionTab(
              strings.t('vpn'),
              Icons.vpn_key_outlined,
              const VpnScreen(),
            ),
            _SectionTab(
              strings.t('system'),
              Icons.info_outline,
              const SystemScreen(),
            ),
          ],
        ),
      ),
      const _PrimaryDestination(
        label: 'More',
        icon: Icons.more_horiz,
        selectedIcon: Icons.more,
        child: _MoreSection(),
      ),
    ];

    final maxIndex = destinations.length - 1;
    final index = _selectedIndex < 0
        ? 0
        : (_selectedIndex > maxIndex ? maxIndex : _selectedIndex);
    final width = MediaQuery.sizeOf(context).width;
    final usesRail = width >= 600;
    final extendRail = width >= 1100;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: _ProfileTitle(profile: selectedProfile),
        actions: [
          _ProfileMenu(
            profiles: profiles.profiles,
            selectedProfile: selectedProfile,
            onSelected: _selectProfile,
          ),
          const _ConnectionAction(),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          if (usesRail)
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _setSelectedDestination,
              extended: extendRail,
              labelType: extendRail
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              minWidth: 72,
              minExtendedWidth: 200,
              leading: extendRail
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        children: [
                          const PfSenseBrandMark(size: 32, elevation: false),
                          const SizedBox(width: 10),
                          Text(
                            'pfSense Manager',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: PfSenseBrandMark(size: 42, elevation: false),
                    ),
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          if (usesRail) const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const _ConnectionStrip(),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: [for (final item in destinations) item.child],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: usesRail
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _setSelectedDestination,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }
}

class _PrimaryDestination {
  const _PrimaryDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
}

class _SectionTab {
  const _SectionTab(this.label, this.icon, this.child);

  final String label;
  final IconData icon;
  final Widget child;
}

class _TabbedSection extends StatefulWidget {
  const _TabbedSection({required this.tabs});

  final List<_SectionTab> tabs;

  @override
  State<_TabbedSection> createState() => _TabbedSectionState();
}

class _TabbedSectionState extends State<_TabbedSection>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _controller;
  int _index = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: widget.tabs.length, vsync: this);
    _controller.addListener(() {
      if (!_controller.indexIsChanging && _controller.index != _index) {
        setState(() => _index = _controller.index);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _controller,
            isScrollable: widget.tabs.length > 3,
            tabs: [
              for (final tab in widget.tabs)
                Tab(icon: Icon(tab.icon), text: tab.label),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [for (final tab in widget.tabs) tab.child],
          ),
        ),
      ],
    );
  }
}

class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({required this.profile});

  final PfSenseProfile? profile;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final status = session.connecting
        ? 'Connecting'
        : session.connected
        ? 'Connected'
        : session.connectionError != null
        ? 'Connection error'
        : 'Disconnected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          profile?.name ?? 'pfSense Manager',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(status, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({
    required this.profiles,
    required this.selectedProfile,
    required this.onSelected,
  });

  static const _manageValue = '__manage_profiles__';

  final List<PfSenseProfile> profiles;
  final PfSenseProfile? selectedProfile;
  final ValueChanged<PfSenseProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Switch firewall',
      icon: const Icon(Icons.expand_more),
      onSelected: (value) {
        if (value == _manageValue) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfilesScreen()));
          return;
        }
        final matches = profiles.where((profile) => profile.id == value);
        if (matches.isNotEmpty) onSelected(matches.first);
      },
      itemBuilder: (context) => [
        for (final profile in profiles)
          PopupMenuItem<String>(
            value: profile.id,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                profile.id == selectedProfile?.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(profile.name),
              subtitle: Text(
                profile.baseUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _manageValue,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.storage_outlined),
            title: Text('Manage profiles'),
          ),
        ),
      ],
    );
  }
}

class _ConnectionAction extends StatelessWidget {
  const _ConnectionAction();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().selectedProfile;
    final session = context.watch<PfSenseSessionProvider>();

    if (session.connecting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      tooltip: session.connected ? 'Disconnect' : 'Connect',
      onPressed: profile == null
          ? null
          : () {
              if (session.connected) {
                session.disconnect();
              } else {
                session.connect(profile);
              }
            },
      icon: Icon(session.connected ? Icons.link_off : Icons.link),
    );
  }
}

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().selectedProfile;
    final session = context.watch<PfSenseSessionProvider>();

    if (profile == null) {
      return Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber_rounded),
          title: const Text('No firewall profile selected'),
          trailing: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfilesScreen())),
            child: const Text('Add profile'),
          ),
        ),
      );
    }

    if (session.connectionError == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.error_outline),
        title: Text(
          session.connectionError!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: session.connecting ? null : () => session.connect(profile),
          child: const Text('Retry'),
        ),
      ),
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Firewall profiles'),
            subtitle: const Text('Add, edit, import or test connections'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfilesScreen())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Hardware health'),
            subtitle: const Text('CPU temps, SMART drive status and memory trends'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HardwareHealthScreen()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Settings'),
            subtitle: const Text('Appearance, language and app security'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ),
      ],
    );
  }
}
