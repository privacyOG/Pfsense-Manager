import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../services/dashboard_warning_preferences.dart';

class DashboardAlertStrip extends StatefulWidget {
  const DashboardAlertStrip({
    super.key,
    required this.data,
    required this.profileId,
  });

  final DashboardData data;
  final String? profileId;

  @override
  State<DashboardAlertStrip> createState() => _DashboardAlertStripState();
}

class _DashboardAlertStripState extends State<DashboardAlertStrip> {
  DashboardWarningPreferences? _preferences;
  Set<DashboardWarningKind> _ignored = const {};
  Map<DashboardWarningKind, DateTime> _snoozed = const {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void didUpdateWidget(covariant DashboardAlertStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _loadPreferences();
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final generation = ++_loadGeneration;
    final profileId = widget.profileId;
    if (profileId == null) {
      if (mounted) {
        setState(() {
          _preferences = null;
          _ignored = const {};
          _snoozed = const {};
        });
      }
      return;
    }

    final preferences = await DashboardWarningPreferences.open();
    final ignored = preferences.ignoredForProfile(profileId);
    final snoozed = preferences.snoozedForProfile(profileId);
    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      _preferences = preferences;
      _ignored = ignored;
      _snoozed = snoozed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _buildWarnings(widget.data);
    if (active.isEmpty) {
      return const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _AlertChip(
            alert: _DashboardAlert(
              kind: null,
              icon: Icons.verified_outlined,
              label: 'No active alerts',
              value: 'System telemetry looks healthy',
              color: Color(0xFF00C2A8),
              details: 'No dashboard warning threshold is currently active.',
              recommendation: 'Continue normal monitoring.',
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final visible = <_DashboardAlert>[];
    var suppressedCount = 0;
    for (final alert in active) {
      final kind = alert.kind!;
      final snoozedUntil = _snoozed[kind];
      final suppressed = _ignored.contains(kind) ||
          (snoozedUntil != null && snoozedUntil.isAfter(now));
      if (suppressed) {
        suppressedCount++;
      } else {
        visible.add(alert);
      }
    }

    final chips = <Widget>[
      for (final alert in visible)
        _AlertChip(
          alert: alert,
          onTap: () => _showDetails(alert),
        ),
    ];
    if (suppressedCount > 0) {
      chips.add(
        _AlertChip(
          alert: _DashboardAlert(
            kind: null,
            icon: Icons.visibility_off_outlined,
            label: 'Warnings hidden',
            value: '$suppressedCount suppressed',
            color: Theme.of(context).colorScheme.outline,
            details:
                '$suppressedCount active warning${suppressedCount == 1 ? ' is' : 's are'} ignored or temporarily snoozed for this firewall profile.',
            recommendation:
                'Ignored warnings can be restored from Settings. Snoozed warnings return automatically after 24 hours.',
          ),
          onTap: () => _showHiddenDetails(suppressedCount),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Future<void> _showDetails(_DashboardAlert alert) async {
    final profileId = widget.profileId;
    final preferences = _preferences;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(alert.icon, color: alert.color, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.label,
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                          Text(
                            alert.value,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: alert.color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'What this means',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(alert.details),
                const SizedBox(height: 16),
                Text(
                  'Recommended check',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(alert.recommendation),
                const SizedBox(height: 22),
                if (profileId != null && preferences != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _snooze(alert);
                      },
                      icon: const Icon(Icons.schedule),
                      label: const Text('Remind me later'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _ignore(alert);
                      },
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('Ignore warning'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remind me later hides this warning for 24 hours. Ignored warnings stay hidden for this profile until restored in Settings.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ] else
                  Text(
                    'Select a firewall profile before changing warning visibility.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showHiddenDetails(int count) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hidden dashboard warnings'),
        content: Text(
          '$count active warning${count == 1 ? ' is' : 's are'} currently ignored or snoozed for this firewall profile. Ignored warnings can be restored in Settings; snoozed warnings reappear automatically after 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _ignore(_DashboardAlert alert) async {
    final profileId = widget.profileId;
    final preferences = _preferences;
    final kind = alert.kind;
    if (profileId == null || preferences == null || kind == null) return;

    await preferences.ignore(profileId, kind);
    if (!mounted) return;
    setState(() {
      _ignored = {..._ignored, kind};
      _snoozed = {..._snoozed}..remove(kind);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${alert.label} ignored for this profile.')),
    );
  }

  Future<void> _snooze(_DashboardAlert alert) async {
    final profileId = widget.profileId;
    final preferences = _preferences;
    final kind = alert.kind;
    if (profileId == null || preferences == null || kind == null) return;

    final until = DateTime.now().add(
      DashboardWarningPreferences.defaultSnoozeDuration,
    );
    await preferences.snooze(profileId, kind, now: DateTime.now());
    if (!mounted) return;
    setState(() => _snoozed = {..._snoozed, kind: until});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${alert.label} snoozed for 24 hours.')),
    );
  }
}

List<_DashboardAlert> _buildWarnings(DashboardData data) {
  final alerts = <_DashboardAlert>[];
  if (data.cpuUsage >= 85) {
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.cpuHigh,
        icon: Icons.memory,
        label: 'CPU high',
        value: '${data.cpuUsage.toStringAsFixed(1)}%',
        color: Colors.redAccent,
        details:
            'Average CPU utilisation has reached the dashboard warning threshold of 85%. Sustained load can delay packet filtering, VPN processing and the web interface.',
        recommendation:
            'Review System Activity, running packages, VPN load and traffic spikes. Confirm whether the value remains high across several refreshes.',
      ),
    );
  }
  if (data.memoryUsage >= 85) {
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.memoryHigh,
        icon: Icons.developer_board,
        label: 'RAM high',
        value: '${data.memoryUsage.toStringAsFixed(1)}%',
        color: Colors.orangeAccent,
        details:
            'Memory usage has reached the dashboard warning threshold of 85%. Continued growth may cause swapping or service instability.',
        recommendation:
            'Review memory-heavy packages and services, check swap usage, and compare the reading after the next refresh.',
      ),
    );
  }
  if (data.diskUsage >= 90) {
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.diskHigh,
        icon: Icons.storage,
        label: 'Disk high',
        value: '${data.diskUsage.toStringAsFixed(1)}%',
        color: Colors.redAccent,
        details:
            'Filesystem usage has reached the dashboard warning threshold of 90%. A full filesystem can prevent logs, configuration changes and package updates from being written.',
        recommendation:
            'Review log retention, crash dumps, package data and available filesystem space before usage reaches 100%.',
      ),
    );
  }

  final hottest = data.temperatureC;
  if (hottest != null && hottest >= 75) {
    String? sensorName;
    for (final sensor in data.thermalSensors) {
      if (sensor.temperatureC == hottest) {
        sensorName = sensor.name;
        break;
      }
    }
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.thermalHigh,
        icon: Icons.device_thermostat,
        label: sensorName == null ? 'Thermal alert' : '$sensorName hot',
        value: '${hottest.toStringAsFixed(1)} °C',
        color: Colors.redAccent,
        details:
            'The hottest reported CPU sensor has reached the 75 °C warning threshold. The displayed value is a Celsius reading reported by pfSense.',
        recommendation:
            'Check airflow, fan operation, dust buildup, ambient temperature and sustained CPU load. Confirm the sensor remains elevated across several refreshes.',
      ),
    );
  }

  final downInterfaces = data.interfaces.where((item) => !item.up).toList();
  if (downInterfaces.isNotEmpty) {
    final names = downInterfaces.map((item) => item.description).join(', ');
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.interfaceDown,
        icon: Icons.settings_ethernet,
        label: 'Interface down',
        value: '${downInterfaces.length} affected',
        color: Colors.orangeAccent,
        details: 'The following interfaces are not reporting an up state: $names.',
        recommendation:
            'Confirm whether each interface is expected to be disconnected. Check cabling, link state, VLAN assignment and interface configuration.',
      ),
    );
  }

  final downGateways = data.gateways.where((item) => !item.online).toList();
  if (downGateways.isNotEmpty) {
    final names = downGateways.map((item) => item.name).join(', ');
    alerts.add(
      _DashboardAlert(
        kind: DashboardWarningKind.gatewayLoss,
        icon: Icons.public_off,
        label: 'Gateway loss',
        value: '${downGateways.length} affected',
        color: Colors.redAccent,
        details: 'The following gateways are not reporting online: $names.',
        recommendation:
            'Review gateway monitoring status, packet loss, monitor IP reachability, upstream connectivity and failover behaviour.',
      ),
    );
  }

  return alerts;
}

class _DashboardAlert {
  const _DashboardAlert({
    required this.kind,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.details,
    required this.recommendation,
  });

  final DashboardWarningKind? kind;
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String details;
  final String recommendation;
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({required this.alert, this.onTap});

  final _DashboardAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: alert.color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: alert.color.withOpacity(0.36)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(alert.icon, color: alert.color, size: 18),
              const SizedBox(width: 8),
              Text(alert.label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(width: 8),
              Text(alert.value, style: Theme.of(context).textTheme.labelSmall),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: alert.color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
