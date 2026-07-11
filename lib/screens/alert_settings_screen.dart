import 'package:flutter/material.dart';

import '../services/alert_service.dart';
import '../services/background_alert_diagnostics.dart';
import '../widgets/background_alert_health_card.dart';

class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  bool _enabled = false;
  bool _gatewayAlerts = true;
  double _cpuTempThreshold = 80;
  double _packetLossThreshold = 15;
  BackgroundAlertDiagnostics _diagnostics =
      const BackgroundAlertDiagnostics();
  bool _loading = true;
  bool _saving = false;
  bool _refreshingDiagnostics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      AlertService.isEnabled(),
      AlertService.getCpuTempThreshold(),
      AlertService.getPacketLossThreshold(),
      AlertService.getGatewayAlertsEnabled(),
      AlertService.getDiagnostics(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = results[0] as bool;
      _cpuTempThreshold = results[1] as double;
      _packetLossThreshold = results[2] as double;
      _gatewayAlerts = results[3] as bool;
      _diagnostics = results[4] as BackgroundAlertDiagnostics;
      _loading = false;
    });
  }

  Future<void> _refreshDiagnostics() async {
    if (_refreshingDiagnostics) return;
    setState(() => _refreshingDiagnostics = true);
    try {
      final diagnostics = await AlertService.getDiagnostics();
      if (mounted) setState(() => _diagnostics = diagnostics);
    } finally {
      if (mounted) setState(() => _refreshingDiagnostics = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      await AlertService.setAlertsEnabled(value);
      final diagnostics = await AlertService.getDiagnostics();
      if (mounted) {
        setState(() {
          _enabled = value;
          _diagnostics = diagnostics;
        });
      }
    } catch (e) {
      final diagnostics = await AlertService.getDiagnostics();
      if (mounted) {
        setState(() => _diagnostics = diagnostics);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setCpuTemp(double value) async {
    setState(() => _cpuTempThreshold = value);
    await AlertService.setCpuTempThreshold(value);
  }

  Future<void> _setPacketLoss(double value) async {
    setState(() => _packetLossThreshold = value);
    await AlertService.setPacketLossThreshold(value);
  }

  Future<void> _setGatewayAlerts(bool value) async {
    setState(() => _gatewayAlerts = value);
    await AlertService.setGatewayAlertsEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Background Alerts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Background monitoring',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (_saving)
                            const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch(
                              value: _enabled,
                              onChanged: _setEnabled,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When enabled, pfSense Manager checks your firewall every 15 minutes in the background and sends a local notification if a threshold is exceeded.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BackgroundAlertHealthCard(
                  enabled: _enabled,
                  diagnostics: _diagnostics,
                  refreshing: _refreshingDiagnostics,
                  onRefresh: _refreshDiagnostics,
                ),
                const SizedBox(height: 24),
                Text(
                  'Alert conditions',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.hub_outlined),
                    title: const Text('Gateway offline'),
                    subtitle: const Text(
                      'Alert when a monitored gateway goes down',
                    ),
                    value: _gatewayAlerts,
                    onChanged: _enabled ? _setGatewayAlerts : null,
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.thermostat_outlined),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('CPU temperature threshold'),
                            ),
                            Text(
                              '${_cpuTempThreshold.toStringAsFixed(0)}°C',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        Slider(
                          value: _cpuTempThreshold,
                          min: 50,
                          max: 100,
                          divisions: 10,
                          onChanged: _enabled ? _setCpuTemp : null,
                        ),
                        Text(
                          'Notify when any sensor exceeds this temperature',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.signal_wifi_bad_outlined),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Packet loss threshold'),
                            ),
                            Text(
                              '${_packetLossThreshold.toStringAsFixed(0)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        Slider(
                          value: _packetLossThreshold,
                          min: 5,
                          max: 50,
                          divisions: 9,
                          onChanged: _enabled ? _setPacketLoss : null,
                        ),
                        Text(
                          'Notify when gateway packet loss exceeds this value',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Background checks run approximately every 15 minutes when connected to the network. Android may delay or batch tasks based on battery optimization settings.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
