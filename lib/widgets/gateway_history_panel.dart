import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/dashboard.dart';

class GatewayHistorySample {
  const GatewayHistorySample({
    required this.capturedAt,
    required this.latencyMs,
    required this.packetLossPercent,
  });

  final DateTime capturedAt;
  final double latencyMs;
  final double packetLossPercent;
}

class GatewayHistorySection extends StatefulWidget {
  const GatewayHistorySection({
    super.key,
    required this.gateways,
    this.maxSamples = 60,
  });

  final List<GatewayStatus> gateways;
  final int maxSamples;

  @override
  State<GatewayHistorySection> createState() => _GatewayHistorySectionState();
}

class _GatewayHistorySectionState extends State<GatewayHistorySection> {
  final Map<String, List<GatewayHistorySample>> _history = {};

  @override
  void initState() {
    super.initState();
    _record(widget.gateways);
  }

  @override
  void didUpdateWidget(covariant GatewayHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _record(widget.gateways);
  }

  void _record(List<GatewayStatus> gateways) {
    final now = DateTime.now();
    final activeNames = gateways.map((gateway) => gateway.name).toSet();
    _history.removeWhere((name, _) => !activeNames.contains(name));

    for (final gateway in gateways) {
      final samples = _history.putIfAbsent(gateway.name, () => []);
      samples.add(
        GatewayHistorySample(
          capturedAt: now,
          latencyMs: math.max(0, gateway.latency),
          packetLossPercent: gateway.packetLoss.clamp(0.0, 100.0),
        ),
      );
      if (samples.length > widget.maxSamples) {
        samples.removeRange(0, samples.length - widget.maxSamples);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gateways.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gateway history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              'Last ${widget.maxSamples} samples',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final gateway in widget.gateways)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GatewayHistoryPanel(
              gateway: gateway,
              samples: List.unmodifiable(_history[gateway.name] ?? const []),
            ),
          ),
      ],
    );
  }
}

class GatewayHistoryPanel extends StatelessWidget {
  const GatewayHistoryPanel({
    super.key,
    required this.gateway,
    required this.samples,
  });

  final GatewayStatus gateway;
  final List<GatewayHistorySample> samples;

  @override
  Widget build(BuildContext context) {
    final statusColor = gateway.online
        ? const Color(0xFF00C2A8)
        : Colors.redAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gateway.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusBadge(
                  text: gateway.online ? 'Online' : gateway.status,
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _Metric(
                  label: 'Latency',
                  value: '${gateway.latency.toStringAsFixed(1)} ms',
                  color: const Color(0xFF5E9CFF),
                ),
                _Metric(
                  label: 'Packet loss',
                  value: '${gateway.packetLoss.toStringAsFixed(1)}%',
                  color: const Color(0xFFFFB020),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (samples.length < 2)
              SizedBox(
                height: 150,
                child: Center(
                  child: Text(
                    'Collecting gateway samples…',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              _HistoryChart(
                title: 'Latency',
                unit: 'ms',
                color: const Color(0xFF5E9CFF),
                samples: samples,
                values: [for (final sample in samples) sample.latencyMs],
              ),
              const SizedBox(height: 12),
              _HistoryChart(
                title: 'Packet loss',
                unit: '%',
                color: const Color(0xFFFFB020),
                samples: samples,
                values: [
                  for (final sample in samples) sample.packetLossPercent,
                ],
                fixedMaximum: 100,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryChart extends StatefulWidget {
  const _HistoryChart({
    required this.title,
    required this.unit,
    required this.color,
    required this.samples,
    required this.values,
    this.fixedMaximum,
  });

  final String title;
  final String unit;
  final Color color;
  final List<GatewayHistorySample> samples;
  final List<double> values;
  final double? fixedMaximum;

  @override
  State<_HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<_HistoryChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = widget.values.fold<double>(0, math.max);
    final maxY = widget.fixedMaximum ?? _niceScale(peak, minimum: 10);
    final maxX = math.max(1, widget.values.length - 1).toDouble();
    final spots = [
      for (var index = 0; index < widget.values.length; index++)
        FlSpot(index.toDouble(), widget.values[index]),
    ];
    final chartDuration = _touchedIndex == null
        ? const Duration(milliseconds: 250)
        : Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.title} (${widget.unit})',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: widget.color),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 135,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxY / 4,
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
                    reservedSize: 38,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: math.max(1, maxX / 2),
                    getTitlesWidget: (value, meta) {
                      final index = value
                          .round()
                          .clamp(0, widget.samples.length - 1)
                          .toInt();
                      final isStart = index == 0;
                      final isMiddle =
                          (index - (widget.samples.length - 1) / 2).abs() <= 1;
                      final isEnd = index == widget.samples.length - 1;
                      if (!isStart && !isMiddle && !isEnd) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          _formatClock(widget.samples[index].capturedAt),
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
                touchCallback: (event, response) {
                  if (!mounted) return;
                  setState(() {
                    final spots = response?.lineBarSpots;
                    if (event is FlPointerExitEvent ||
                        event is FlPanEndEvent ||
                        spots == null ||
                        spots.isEmpty) {
                      _touchedIndex = null;
                    } else {
                      _touchedIndex = spots.first.spotIndex;
                    }
                  });
                },
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return spotIndexes.map((_) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: widget.color.withValues(alpha: 0.65),
                        strokeWidth: 1.5,
                        dashArray: [4, 3],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: widget.color,
                            strokeWidth: 1.5,
                            strokeColor: scheme.surface,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => scheme.surfaceContainerHigh,
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  getTooltipItems: (spots) {
                    return spots.map((spot) {
                      final idx = spot.spotIndex
                          .clamp(0, widget.samples.length - 1);
                      final time =
                          _formatClock(widget.samples[idx].capturedAt);
                      return LineTooltipItem(
                        '$time\n${spot.y.toStringAsFixed(1)} ${widget.unit}',
                        TextStyle(
                          color: widget.color,
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
                  spots: spots,
                  isCurved: false,
                  color: widget.color,
                  barWidth: 2.2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: widget.color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
            duration: chartDuration,
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label $value'),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

double _niceScale(double peak, {required double minimum}) {
  if (!peak.isFinite || peak <= 0) return minimum;
  final padded = math.max(minimum, peak * 1.15);
  final exponent =
      math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();
  final fraction = padded / exponent;
  final niceFraction = fraction <= 1
      ? 1.0
      : fraction <= 2
          ? 2.0
          : fraction <= 5
              ? 5.0
              : 10.0;
  return math.max(minimum, niceFraction * exponent);
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  return '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
