import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/dashboard.dart';
import '../models/dashboard_layout.dart';
import '../providers/session_provider.dart';
import '../widgets/dashboard_alert_strip.dart';
import '../widgets/thermal_sensors_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _prefLive = 'dashboard.live';
  static const _prefRefreshSeconds = 'dashboard.refreshSeconds';
  static const _prefShowHealth = 'dashboard.showHealth';
  static const _prefShowLoad = 'dashboard.showLoad';
  static const _prefShowGateways = 'dashboard.showGateways';
  static const _prefShowInterfaces = 'dashboard.showInterfaces';
  static const _prefCardOrder = 'dashboard.cardOrder';

  DashboardData? _data;
  Object? _error;
  bool _loading = false;
  bool _live = true;
  bool _appActive = true;
  bool _preferencesLoaded = false;
  int _refreshSeconds = 5;
  bool _showHealth = true;
  bool _showLoad = true;
  bool _showGateways = true;
  bool _showInterfaces = true;
  List<String> _cardOrder = DashboardLayoutSection.defaults.toList();
  Timer? _timer;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardPreferences();
  }

  @override
  void dispose() {
    _requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    if (active && _live && mounted) _refresh();
  }

  Future<void> _loadDashboardPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedInterval = prefs.getInt(_prefRefreshSeconds) ?? 5;
    setState(() {
      _live = prefs.getBool(_prefLive) ?? true;
      _refreshSeconds = const {1, 3, 5, 10}.contains(savedInterval)
          ? savedInterval
          : 5;
      _showHealth = prefs.getBool(_prefShowHealth) ?? true;
      _showLoad = prefs.getBool(_prefShowLoad) ?? true;
      _showGateways = prefs.getBool(_prefShowGateways) ?? true;
      _showInterfaces = prefs.getBool(_prefShowInterfaces) ?? true;
      _cardOrder = DashboardLayout.normalize(
        prefs.getStringList(_prefCardOrder),
      );
      _preferencesLoaded = true;
    });
    _startTimer();
  }

  Future<void> _saveDashboardPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLive, _live);
    await prefs.setInt(_prefRefreshSeconds, _refreshSeconds);
    await prefs.setBool(_prefShowHealth, _showHealth);
    await prefs.setBool(_prefShowLoad, _showLoad);
    await prefs.setBool(_prefShowGateways, _showGateways);
    await prefs.setBool(_prefShowInterfaces, _showInterfaces);
    await prefs.setStringList(_prefCardOrder, _cardOrder);
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_preferencesLoaded) return;
    _timer = Timer.periodic(Duration(seconds: _refreshSeconds), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_live &&
          _appActive &&
          !_loading &&
          session.connected &&
          session.service != null) {
        _refresh();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed =
        _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;

    if (changed) {
      _requestGeneration++;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      _data = null;
      _error = null;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh(showSpinner: true);
        });
      }
    } else if (_data == null && session.connected && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(showSpinner: true);
      });
    }
  }

  Future<void> _refresh({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _error =
            AppLocalizations.of(context)?.disconnectedMessage ?? 'Disconnected';
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });

    try {
      final data = await session.service!.getDashboard();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _reorderCards(int oldIndex, int newIndex) {
    setState(() {
      final item = _cardOrder.removeAt(oldIndex);
      _cardOrder.insert(newIndex, item);
    });
    _saveDashboardPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final data = _data;

    return RefreshIndicator(
      onRefresh: () => _refresh(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            _MessageCard(
              icon: Icons.cloud_off_outlined,
              text: strings?.disconnectedMessage ?? 'Disconnected',
            ),
          if (_error != null)
            _MessageCard(icon: Icons.error_outline, text: _error.toString()),
          if (data == null && !_loading && session.connected)
            _MessageCard(
              icon: Icons.space_dashboard_outlined,
              text: strings?.emptyState ?? 'Nothing to show yet.',
            ),
          if (data != null)
            _DashboardBody(
              data: data,
              profileId: session.selectedProfile?.id,
              live: _live,
              refreshSeconds: _refreshSeconds,
              showHealth: _showHealth,
              showLoad: _showLoad,
              showGateways: _showGateways,
              showInterfaces: _showInterfaces,
              cardOrder: _cardOrder,
              onLiveChanged: (value) {
                setState(() => _live = value);
                _saveDashboardPreferences();
                if (value) _refresh();
              },
              onRefreshSecondsChanged: (value) {
                setState(() => _refreshSeconds = value);
                _startTimer();
                _saveDashboardPreferences();
                if (_live) _refresh();
              },
              onCustomize: _showCustomizeSheet,
              onNocMode: () => _showNocWallboard(data),
              onInterfaceTap: _showInterfaceDetails,
            ),
        ],
      ),
    );
  }

  Future<void> _showCustomizeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void update(VoidCallback change) {
              setState(change);
              setSheetState(() {});
              _saveDashboardPreferences();
            }

            void reorder(int oldIndex, int newIndex) {
              _reorderCards(oldIndex, newIndex);
              setSheetState(() {});
            }

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dashboard layout',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Drag sections into your preferred order. Long-press any dashboard section to return here.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _cardOrder.length,
                        onReorderItem: reorder,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          final id = _cardOrder[index];
                          return Card(
                            key: ValueKey(id),
                            child: ListTile(
                              leading: Icon(_sectionIcon(id)),
                              title: Text(_sectionLabel(id)),
                              subtitle: Text(
                                _sectionVisible(id) ? 'Visible' : 'Hidden',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: _sectionVisible(id),
                                    onChanged: (value) {
                                      update(
                                        () => _setSectionVisible(id, value),
                                      );
                                    },
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _live,
                      onChanged: (value) => update(() => _live = value),
                      title: const Text('Live refresh'),
                      secondary: const Icon(Icons.sync),
                    ),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Refresh interval'),
                      trailing: DropdownButton<int>(
                        value: _refreshSeconds,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 sec')),
                          DropdownMenuItem(value: 3, child: Text('3 sec')),
                          DropdownMenuItem(value: 5, child: Text('5 sec')),
                          DropdownMenuItem(value: 10, child: Text('10 sec')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          update(() => _refreshSeconds = value);
                          _startTimer();
                          if (_live) _refresh();
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            update(() {
                              _cardOrder = DashboardLayoutSection.defaults
                                  .toList();
                            });
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset layout'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _sectionVisible(String id) {
    return switch (id) {
      DashboardLayoutSection.health => _showHealth,
      DashboardLayoutSection.system => _showLoad,
      DashboardLayoutSection.gateways => _showGateways,
      DashboardLayoutSection.interfaces => _showInterfaces,
      _ => true,
    };
  }

  void _setSectionVisible(String id, bool value) {
    switch (id) {
      case DashboardLayoutSection.health:
        _showHealth = value;
      case DashboardLayoutSection.system:
        _showLoad = value;
      case DashboardLayoutSection.gateways:
        _showGateways = value;
      case DashboardLayoutSection.interfaces:
        _showInterfaces = value;
    }
  }

  void _showNocWallboard(DashboardData data) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _NocWallboard(data: data),
      ),
    );
  }

  Future<void> _showInterfaceDetails(InterfaceStatus interface) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _InterfaceDetailSheet(interface: interface),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.profileId,
    required this.live,
    required this.refreshSeconds,
    required this.showHealth,
    required this.showLoad,
    required this.showGateways,
    required this.showInterfaces,
    required this.cardOrder,
    required this.onLiveChanged,
    required this.onRefreshSecondsChanged,
    required this.onCustomize,
    required this.onNocMode,
    required this.onInterfaceTap,
  });

  final DashboardData data;
  final String? profileId;
  final bool live;
  final int refreshSeconds;
  final bool showHealth;
  final bool showLoad;
  final bool showGateways;
  final bool showInterfaces;
  final List<String> cardOrder;
  final ValueChanged<bool> onLiveChanged;
  final ValueChanged<int> onRefreshSecondsChanged;
  final VoidCallback onCustomize;
  final VoidCallback onNocMode;
  final ValueChanged<InterfaceStatus> onInterfaceTap;

  @override
  Widget build(BuildContext context) {
    final onlineGateways = data.gateways.where((gateway) => gateway.online);
    final upInterfaces = data.interfaces.where((interface) => interface.up);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroPanel(
          title: data.platform,
          subtitle: data.cpuModel,
          uptime: data.uptime,
          onlineGateways: onlineGateways.length,
          totalGateways: data.gateways.length,
          upInterfaces: upInterfaces.length,
          totalInterfaces: data.interfaces.length,
          live: live,
          onLiveChanged: onLiveChanged,
          refreshSeconds: refreshSeconds,
          onRefreshSecondsChanged: onRefreshSecondsChanged,
          onCustomize: onCustomize,
          onNocMode: onNocMode,
        ),
        const SizedBox(height: 14),
        DashboardAlertStrip(data: data, profileId: profileId),
        const SizedBox(height: 14),
        for (final id in cardOrder)
          if (_isVisible(id))
            _DashboardSection(
              key: ValueKey(id),
              onLongPress: onCustomize,
              child: _buildSection(context, id),
            ),
      ],
    );
  }

  bool _isVisible(String id) {
    return switch (id) {
      DashboardLayoutSection.health => showHealth,
      DashboardLayoutSection.system => showLoad,
      DashboardLayoutSection.gateways => showGateways,
      DashboardLayoutSection.interfaces => showInterfaces,
      _ => false,
    };
  }

  Widget _buildSection(BuildContext context, String id) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final onlineGateways = data.gateways.where((gateway) => gateway.online);
    final upInterfaces = data.interfaces.where((interface) => interface.up);

    return switch (id) {
      DashboardLayoutSection.health => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.speed,
            title: 'Health gauges',
            action: 'Long-press to arrange',
          ),
          const SizedBox(height: 10),
          _ResponsiveGrid(
            minTileWidth: wide ? 220 : 150,
            children: [
              _MetricGauge(
                icon: Icons.memory_outlined,
                label: 'CPU',
                value: data.cpuUsage,
                detail: data.cpuCount > 0 ? '${data.cpuCount} cores' : 'Load',
                color: const Color(0xFF00C2A8),
              ),
              _MetricGauge(
                icon: Icons.developer_board_outlined,
                label: 'Memory',
                value: data.memoryUsage,
                detail: 'RAM in use',
                color: const Color(0xFF5E9CFF),
              ),
              _MetricGauge(
                icon: Icons.storage_outlined,
                label: 'Disk',
                value: data.diskUsage,
                detail: 'Filesystem used',
                color: const Color(0xFFFFB020),
              ),
              _MetricGauge(
                icon: Icons.swap_horiz,
                label: 'Swap',
                value: data.swapUsage,
                detail: 'Swap used',
                color: const Color(0xFFB36BFF),
              ),
            ],
          ),
          const SizedBox(height: 22),
        ],
      ),
      DashboardLayoutSection.system => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.device_thermostat,
            title: 'System load and thermal',
            action: 'Long-press to arrange',
          ),
          const SizedBox(height: 10),
          _ResponsiveGrid(
            minTileWidth: wide ? 320 : 240,
            children: [
              _LoadCard(data: data),
              _MiniUsageCard(
                icon: Icons.hub_outlined,
                title: 'MBUF',
                value: data.mbufUsage,
                subtitle: 'Network buffer usage',
              ),
            ],
          ),
          const SizedBox(height: 14),
          ThermalSensorsPanel(
            sensors: data.thermalSensors,
            fallbackTemperatureC: data.temperatureC,
          ),
          const SizedBox(height: 22),
        ],
      ),
      DashboardLayoutSection.gateways => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.public_outlined,
            title: 'Gateways',
            action: data.gateways.isEmpty
                ? 'Not reported'
                : '${onlineGateways.length}/${data.gateways.length} online',
          ),
          const SizedBox(height: 10),
          if (data.gateways.isEmpty)
            const _EmptyPanel('No gateway telemetry returned by pfSense.')
          else
            _ResponsiveGrid(
              minTileWidth: wide ? 300 : 260,
              children: data.gateways.map(_GatewayCard.new).toList(),
            ),
          const SizedBox(height: 22),
        ],
      ),
      DashboardLayoutSection.interfaces => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.settings_ethernet,
            title: 'Interfaces',
            action: data.interfaces.isEmpty
                ? 'Not reported'
                : '${upInterfaces.length}/${data.interfaces.length} up',
          ),
          const SizedBox(height: 10),
          if (data.interfaces.isEmpty)
            const _EmptyPanel('No interface telemetry returned by pfSense.')
          else
            _ResponsiveGrid(
              minTileWidth: wide ? 330 : 280,
              children: data.interfaces
                  .map(
                    (interface) => _InterfaceCard(
                      interface,
                      onTap: () => onInterfaceTap(interface),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 22),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    super.key,
    required this.child,
    required this.onLongPress,
  });

  final Widget child;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

String _sectionLabel(String id) {
  return switch (id) {
    DashboardLayoutSection.health => 'Health gauges',
    DashboardLayoutSection.system => 'Load, thermal and buffers',
    DashboardLayoutSection.gateways => 'Gateways',
    DashboardLayoutSection.interfaces => 'Interfaces',
    _ => id,
  };
}

IconData _sectionIcon(String id) {
  return switch (id) {
    DashboardLayoutSection.health => Icons.speed,
    DashboardLayoutSection.system => Icons.device_thermostat,
    DashboardLayoutSection.gateways => Icons.public,
    DashboardLayoutSection.interfaces => Icons.settings_ethernet,
    _ => Icons.dashboard_customize,
  };
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.uptime,
    required this.onlineGateways,
    required this.totalGateways,
    required this.upInterfaces,
    required this.totalInterfaces,
    required this.live,
    required this.onLiveChanged,
    required this.refreshSeconds,
    required this.onRefreshSecondsChanged,
    required this.onCustomize,
    required this.onNocMode,
  });

  final String title;
  final String subtitle;
  final String uptime;
  final int onlineGateways;
  final int totalGateways;
  final int upInterfaces;
  final int totalInterfaces;
  final bool live;
  final ValueChanged<bool> onLiveChanged;
  final int refreshSeconds;
  final ValueChanged<int> onRefreshSecondsChanged;
  final VoidCallback onCustomize;
  final VoidCallback onNocMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C2A8).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security, color: Color(0xFF00C2A8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'NOC wallboard',
                onPressed: onNocMode,
                icon: const Icon(Icons.monitor),
              ),
              IconButton(
                tooltip: 'Customize dashboard',
                onPressed: onCustomize,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusPill(Icons.schedule, 'Uptime', uptime),
              _StatusPill(
                Icons.public,
                'Gateways',
                totalGateways == 0 ? 'n/a' : '$onlineGateways/$totalGateways',
              ),
              _StatusPill(
                Icons.settings_ethernet,
                'Interfaces',
                totalInterfaces == 0 ? 'n/a' : '$upInterfaces/$totalInterfaces',
              ),
              FilterChip(
                selected: live,
                avatar: Icon(live ? Icons.sync : Icons.sync_disabled),
                label: Text(live ? 'Live ${refreshSeconds}s' : 'Paused'),
                onSelected: onLiveChanged,
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1s')),
                  ButtonSegment(value: 3, label: Text('3s')),
                  ButtonSegment(value: 5, label: Text('5s')),
                  ButtonSegment(value: 10, label: Text('10s')),
                ],
                selected: {refreshSeconds},
                onSelectionChanged: (values) =>
                    onRefreshSecondsChanged(values.first),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, required this.minTileWidth});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);
        return GridView.count(
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 1 ? 1.75 : 1.45,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _MetricGauge extends StatelessWidget {
  const _MetricGauge({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = (value / 100).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: percent,
                    strokeWidth: 8,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.14),
                    strokeCap: StrokeCap.round,
                  ),
                  Icon(icon, color: color),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${value.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(icon: Icons.speed, title: 'Load average'),
            const Spacer(),
            Row(
              children: [
                _LoadValue('1m', data.loadAverage1),
                _LoadValue('5m', data.loadAverage5),
                _LoadValue('15m', data.loadAverage15),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniUsageCard extends StatelessWidget {
  const _MiniUsageCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final double value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(icon: icon, title: title),
            const Spacer(),
            LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 9,
              color: color,
              backgroundColor: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 10),
            Text('${value.toStringAsFixed(1)}%'),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard(this.gateway);

  final GatewayStatus gateway;

  @override
  Widget build(BuildContext context) {
    final color = gateway.online ? const Color(0xFF00C2A8) : Colors.redAccent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    gateway.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _Badge(gateway.status, color),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                _Stat('Latency', '${gateway.latency.toStringAsFixed(1)} ms'),
                _Stat('Loss', '${gateway.packetLoss.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              gateway.monitorIp ?? gateway.substatus ?? 'Monitor unavailable',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard(this.interface, {required this.onTap});

  final InterfaceStatus interface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = interface.up ? const Color(0xFF00C2A8) : Colors.orangeAccent;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_ethernet, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      interface.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _Badge(interface.status, color),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  interface.name,
                  if (interface.hardwareInterface.isNotEmpty)
                    interface.hardwareInterface,
                  if (interface.ipv4Address != null) interface.ipv4Address!,
                ].join('  |  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Row(
                children: [
                  _Stat('In', _formatBytes(interface.bytesIn)),
                  _Stat('Out', _formatBytes(interface.bytesOut)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Stat(
                    'Packets',
                    _formatCount(interface.packetsIn + interface.packetsOut),
                  ),
                  _Stat(
                    'Errors',
                    _formatCount(interface.errorsIn + interface.errorsOut),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterfaceDetailSheet extends StatelessWidget {
  const _InterfaceDetailSheet({required this.interface});

  final InterfaceStatus interface;

  @override
  Widget build(BuildContext context) {
    final color = interface.up ? const Color(0xFF00C2A8) : Colors.orangeAccent;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          Row(
            children: [
              Icon(Icons.settings_ethernet, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  interface.description,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _Badge(interface.status, color),
            ],
          ),
          const SizedBox(height: 14),
          _DetailRows(
            rows: {
              'Name': interface.name,
              'Hardware': interface.hardwareInterface.isEmpty
                  ? 'Not reported'
                  : interface.hardwareInterface,
              'IPv4': interface.ipv4Address ?? 'Not reported',
              'IPv6': interface.ipv6Address ?? 'Not reported',
              'Gateway': interface.gateway ?? 'Not reported',
              'Media': interface.media ?? 'Not reported',
              'In bytes': _formatBytes(interface.bytesIn),
              'Out bytes': _formatBytes(interface.bytesOut),
              'In packets': _formatCount(interface.packetsIn),
              'Out packets': _formatCount(interface.packetsOut),
              'Errors': _formatCount(interface.errorsIn + interface.errorsOut),
              'Collisions': _formatCount(interface.collisions),
            },
          ),
        ],
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final entry in rows.entries) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      entry.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              if (entry.key != rows.keys.last) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _NocWallboard extends StatelessWidget {
  const _NocWallboard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final onlineGateways = data.gateways
        .where((gateway) => gateway.online)
        .length;
    final upInterfaces = data.interfaces
        .where((interface) => interface.up)
        .length;
    final hottest = data.temperatureC;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NOC Wallboard'),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: MediaQuery.sizeOf(context).width >= 900 ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          _WallboardTile(
            'CPU',
            '${data.cpuUsage.toStringAsFixed(1)}%',
            Icons.memory,
            _usageColor(data.cpuUsage),
          ),
          _WallboardTile(
            'RAM',
            '${data.memoryUsage.toStringAsFixed(1)}%',
            Icons.developer_board,
            _usageColor(data.memoryUsage),
          ),
          _WallboardTile(
            'Disk',
            '${data.diskUsage.toStringAsFixed(1)}%',
            Icons.storage,
            _usageColor(data.diskUsage),
          ),
          _WallboardTile(
            'Interfaces',
            '$upInterfaces/${data.interfaces.length}',
            Icons.settings_ethernet,
            const Color(0xFF00C2A8),
          ),
          _WallboardTile(
            'Gateways',
            '$onlineGateways/${data.gateways.length}',
            Icons.public,
            const Color(0xFF5E9CFF),
          ),
          _WallboardTile(
            'Hottest sensor',
            hottest == null ? 'n/a' : '${hottest.toStringAsFixed(1)} °C',
            Icons.device_thermostat,
            hottest == null ? Colors.grey : thermalColor(hottest),
          ),
          _WallboardTile(
            'Thermal sensors',
            data.thermalSensors.length.toString(),
            Icons.thermostat,
            const Color(0xFF00C2A8),
          ),
        ],
      ),
    );
  }
}

class _WallboardTile extends StatelessWidget {
  const _WallboardTile(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 34),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

Color _usageColor(double value) {
  if (value >= 90) return Colors.redAccent;
  if (value >= 75) return Colors.orangeAccent;
  return const Color(0xFF00C2A8);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text(action, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surface.withValues(alpha: 0.62),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadValue extends StatelessWidget {
  const _LoadValue(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value.toStringAsFixed(2),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(text)),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

String _formatCount(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
