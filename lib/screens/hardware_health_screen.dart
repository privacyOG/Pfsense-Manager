import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dashboard.dart';
import '../models/smart_drive.dart';
import '../providers/session_provider.dart';
import '../services/hardware_health_loader.dart';
import '../services/pfrest_feature_registry.dart';
import '../widgets/pfrest_feature_gate.dart';
import '../widgets/state_message.dart';
import '../widgets/thermal_sensors_panel.dart';

class HardwareHealthScreen extends StatefulWidget {
  const HardwareHealthScreen({super.key});

  @override
  State<HardwareHealthScreen> createState() => _HardwareHealthScreenState();
}

class _HardwareHealthScreenState extends State<HardwareHealthScreen> {
  static const _maxSamples = 30;

  DashboardData? _data;
  List<SmartDrive> _drives = const [];
  String? _healthError;
  String? _smartError;
  bool _loading = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;
  final _memSamples = <_UsageSample>[];
  final _swapSamples = <_UsageSample>[];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (changed) {
      _requestGeneration++;
      _data = null;
      _drives = const [];
      _healthError = null;
      _smartError = null;
      _lastSuccessfulRefresh = null;
      _memSamples.clear();
      _swapSamples.clear();
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    } else if (_data == null && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _refreshTimer?.cancel();
    super.dispose();
  }

  PfRestFeatureDecision _smartDecision(PfSenseSessionProvider session) {
    return PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    ).decision(PfRestFeature.smartStatus);
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _drives = const [];
        _healthError = 'Disconnected';
        _smartError = null;
        _lastSuccessfulRefresh = null;
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    final smartDecision = _smartDecision(session);
    setState(() {
      _loading = true;
      _healthError = null;
      _smartError = null;
    });

    try {
      final result = await loadHardwareHealthData(
        loadHealth: session.service!.getHardwareHealth,
        loadSmart: session.service!.getSmartStatus,
        smartDecision: smartDecision,
      );
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }

      final now = DateTime.now();
      _memSamples.add(
        _UsageSample(capturedAt: now, value: result.health.memoryUsage),
      );
      _swapSamples.add(
        _UsageSample(capturedAt: now, value: result.health.swapUsage),
      );
      if (_memSamples.length > _maxSamples) {
        _memSamples.removeRange(0, _memSamples.length - _maxSamples);
      }
      if (_swapSamples.length > _maxSamples) {
        _swapSamples.removeRange(0, _swapSamples.length - _maxSamples);
      }

      setState(() {
        _data = result.health;
        _drives = result.drives;
        _smartError = result.smartError;
        _lastSuccessfulRefresh = now;
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _healthError = error.toString());
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final smartDecision = _smartDecision(session);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _HeaderCard(
            sensorCount:
                session.connected ? (_data?.thermalSensors.length ?? 0) : 0,
            driveCount: session.connected ? _drives.length : 0,
            memUsage: session.connected ? (_data?.memoryUsage ?? 0) : 0,
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)} · auto-refreshes every 30 s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const StateMessage(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_healthError != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _healthError!,
            )
          else if (_data != null) ...[
            ThermalSensorsPanel(
              sensors: _data!.thermalSensors,
              fallbackTemperatureC: _data!.temperatureC,
            ),
            const SizedBox(height: 14),
            if (smartDecision.isUnknown) ...[
              PfRestFeatureNotice(
                decision: smartDecision,
                onRefresh: () => session.refreshCapabilities(),
              ),
              const SizedBox(height: 14),
            ],
            _SmartSection(
              decision: smartDecision,
              drives: _drives,
              error: _smartError,
            ),
            const SizedBox(height: 14),
            _MemorySwapSection(
              memUsage: _data!.memoryUsage,
              swapUsage: _data!.swapUsage,
              memSamples: List.unmodifiable(_memSamples),
              swapSamples: List.unmodifiable(_swapSamples),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

class _UsageSample {
  const _UsageSample({required this.capturedAt, required this.value});

  final DateTime capturedAt;
  final double value;
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.sensorCount,
    required this.driveCount,
    required this.memUsage,
  });

  final int sensorCount;
  final int driveCount;
  final double memUsage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.monitor_heart_outlined,
            color: Color(0xFF00C2A8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hardware Health',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          _MiniStat('Sensors', sensorCount.toString()),
          _MiniStat('Drives', driveCount.toString()),
          _MiniStat('RAM', '${memUsage.toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SmartSection extends StatelessWidget {
  const _SmartSection({
    required this.decision,
    required this.drives,
    required this.error,
  });

  final PfRestFeatureDecision decision;
  final List<SmartDrive> drives;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final status = _statusText();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  decision.isUnsupported
                      ? Icons.extension_off_outlined
                      : Icons.storage_outlined,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Drive health (S.M.A.R.T.)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  drives.isEmpty
                      ? decision.isUnsupported
                          ? 'Unsupported'
                          : 'No drives'
                      : '${drives.length} drive${drives.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(status, style: Theme.of(context).textTheme.bodySmall),
            if (drives.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final drive in drives) _SmartDriveCard(drive: drive),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText() {
    if (decision.isUnsupported) return decision.message;
    if (error != null) return error!;
    if (drives.isEmpty) {
      return decision.isUnknown
          ? 'The direct request completed without drive records while capability discovery remains limited.'
          : 'The supported endpoint returned no SMART drive records.';
    }
    return drives.every((drive) => drive.healthPassed)
        ? 'All reported drives are healthy.'
        : 'One or more reported drives may need attention.';
  }
}

class _SmartDriveCard extends StatelessWidget {
  const _SmartDriveCard({required this.drive});

  final SmartDrive drive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor =
        drive.healthPassed ? const Color(0xFF00C2A8) : scheme.error;
    final statusLabel = drive.healthPassed ? 'PASSED' : 'FAILED';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: .12),
          child: Icon(
            Icons.storage_outlined,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          drive.description.isNotEmpty ? drive.description : drive.device,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(drive.device),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        children: [
          if (drive.temperatureC != null)
            _DriveRow(
              label: 'Temperature',
              value: '${drive.temperatureC!.toStringAsFixed(0)} °C',
              warn: (drive.temperatureC ?? 0) >= 50,
            ),
          if (drive.powerOnHours != null)
            _DriveRow(
              label: 'Power-on time',
              value: _formatHours(drive.powerOnHours!),
            ),
          if (drive.reallocatedSectors != null)
            _DriveRow(
              label: 'Reallocated sectors',
              value: drive.reallocatedSectors.toString(),
              warn: (drive.reallocatedSectors ?? 0) > 0,
            ),
          if (drive.pendingSectors != null)
            _DriveRow(
              label: 'Pending sectors',
              value: drive.pendingSectors.toString(),
              warn: (drive.pendingSectors ?? 0) > 0,
            ),
          if (drive.wearLevelingCount != null)
            _DriveRow(
              label: 'Wear leveling count',
              value: drive.wearLevelingCount.toString(),
            ),
          if (drive.powerOnHours == null &&
              drive.reallocatedSectors == null &&
              drive.pendingSectors == null &&
              drive.wearLevelingCount == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'No detailed SMART attributes were reported for this drive.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _formatHours(int hours) {
    if (hours < 48) return '$hours h';
    if (hours < 24 * 365) return '${(hours / 24).round()} days';
    return '${(hours / 8760).toStringAsFixed(1)} yrs';
  }
}

class _DriveRow extends StatelessWidget {
  const _DriveRow({
    required this.label,
    required this.value,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: warn ? scheme.error : null,
        ),
      ),
    );
  }
}

class _MemorySwapSection extends StatelessWidget {
  const _MemorySwapSection({
    required this.memUsage,
    required this.swapUsage,
    required this.memSamples,
    required this.swapSamples,
  });

  final double memUsage;
  final double swapUsage;
  final List<_UsageSample> memSamples;
  final List<_UsageSample> swapSamples;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Memory & swap',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${memSamples.length} sample${memSamples.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _UsageBar(
              label: 'RAM',
              usage: memUsage,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            _UsageBar(
              label: 'Swap',
              usage: swapUsage,
              color: Colors.orangeAccent,
            ),
            if (memSamples.length >= 2) ...[
              const SizedBox(height: 20),
              _MemSwapChart(
                memSamples: memSamples,
                swapSamples: swapSamples,
                memColor: scheme.primary,
                swapColor: Colors.orangeAccent,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _LegendDot(color: scheme.primary),
                  const SizedBox(width: 5),
                  Text('RAM', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 14),
                  const _LegendDot(color: Colors.orangeAccent),
                  const SizedBox(width: 5),
                  Text('Swap', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Collecting usage samples…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.usage,
    required this.color,
  });

  final String label;
  final double usage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percentage = usage.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: scheme.surfaceContainerHighest,
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MemSwapChart extends StatelessWidget {
  const _MemSwapChart({
    required this.memSamples,
    required this.swapSamples,
    required this.memColor,
    required this.swapColor,
  });

  final List<_UsageSample> memSamples;
  final List<_UsageSample> swapSamples;
  final Color memColor;
  final Color swapColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxX = math.max(1, memSamples.length - 1).toDouble();
    final memSpots = [
      for (var index = 0; index < memSamples.length; index++)
        FlSpot(index.toDouble(), memSamples[index].value),
    ];
    final swapSpots = [
      for (var index = 0; index < swapSamples.length; index++)
        FlSpot(index.toDouble(), swapSamples[index].value),
    ];

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: 100,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 25,
            verticalInterval: math.max(1, maxX / 4),
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: 25,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: math.max(1, maxX / 2),
                getTitlesWidget: (value, _) {
                  final index = value
                      .round()
                      .clamp(0, memSamples.length - 1)
                      .toInt();
                  final isStart = index == 0;
                  final isEnd = index == memSamples.length - 1;
                  final isMiddle =
                      (index - (memSamples.length - 1) / 2).abs() <= 1;
                  if (!isStart && !isMiddle && !isEnd) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _formatClock(memSamples[index].capturedAt),
                      style: const TextStyle(fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.surfaceContainerHigh,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final index = spot.spotIndex.clamp(0, memSamples.length - 1);
                  final time = _formatClock(memSamples[index].capturedAt);
                  final label = spot.barIndex == 0 ? 'RAM' : 'Swap';
                  final color = spot.barIndex == 0 ? memColor : swapColor;
                  return LineTooltipItem(
                    '$label $time\n${spot.y.toStringAsFixed(1)}%',
                    TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: memSpots,
              isCurved: false,
              color: memColor,
              barWidth: 2.2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: memColor.withValues(alpha: .10),
              ),
            ),
            LineChartBarData(
              spots: swapSpots,
              isCurved: false,
              color: swapColor,
              barWidth: 2.2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: swapColor.withValues(alpha: .10),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  return '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
