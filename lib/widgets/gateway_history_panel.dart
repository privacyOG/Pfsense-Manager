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
      final next = GatewayHistorySample(
        capturedAt: now,
        latencyMs: gateway.latency,
        packetLossPercent: gateway.packetLoss,
      );
      if (samples.isEmpty ||
          samples.last.latencyMs != next.latencyMs ||
          samples.last.packetLossPercent != next.packetLossPercent ||
          now.difference(samples.last.capturedAt) >= const Duration(seconds: 1)) {
        samples.add(next);
      }
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
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gateway.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Live latency and packet-loss history',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendItem(
                  label: 'Latency ${gateway.latency.toStringAsFixed(1)} ms',
                  color: const Color(0xFF5E9CFF),
                ),
                _LegendItem(
                  label: 'Loss ${gateway.packetLoss.toStringAsFixed(1)}%',
                  color: const Color(0xFFFFB020),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: samples.length < 2
                  ? const _HistoryPlaceholder()
                  : _GatewayHistoryChart(samples: samples),
            ),
          ],
        ),
      ),
    );
  }
}

class _GatewayHistoryChart extends StatelessWidget {
  const _GatewayHistoryChart({required this.samples});

  final List<GatewayHistorySample> samples;

  @override
  Widget build(BuildContext context) {
    final latencySpots = <FlSpot>[];
    final lossSpots = <FlSpot>[];
    var latencyPeak = 0.0;
    var lossPeak = 0.0;

    for (var index = 0; index < samples.length; index++) {
      final latency = math.max(0, samples[index].latencyMs);
      final loss = samples[index].packetLossPercent.clamp(0.0, 100.0);
      latencyPeak = math.max(latencyPeak, latency);
      lossPeak = math.max(lossPeak, loss);
      latencySpots.add(FlSpot(index.toDouble(), latency));
      lossSpots.add(FlSpot(index.toDouble(), loss));
    }

    final latencyScale = _niceScale(latencyPeak, minimum: 10);
    final lossScale = _niceScale(lossPeak, minimum: 5, maximum: 100);
    final maxX = math.max(1, samples.length - 1).toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: latencyScale,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: latencyScale / 4,
          verticalInterval: math.max(1, maxX / 4),
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.08),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.white.withOpacity(0.18)),
            bottom: BorderSide(color: Colors.white.withOpacity(0.18)),
            right: BorderSide(color: Colors.white.withOpacity(0.18)),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('ms', style: TextStyle(fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: latencyScale / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          rightTitles: AxisTitles(
            axisNameWidget: const Text('%', style: TextStyle(fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: latencyScale / 4,
              getTitlesWidget: (value, meta) {
                final lossValue = latencyScale <= 0
                    ? 0
                    : (value / latencyScale) * lossScale;
                return Text(
                  lossValue.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: math.max(1, maxX / 2),
              getTitlesWidget: (value, meta) {
                final index = value.round().clamp(0, samples.length - 1);
                final isStart = index == 0;
                final isMiddle =
                    (index - (samples.length - 1) / 2).abs() <= 1;
                final isEnd = index == samples.length - 1;
                if (!isStart && !isMiddle && !isEnd) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _formatClock(samples[index].capturedAt),
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              if (spot.barIndex == 0) {
                return LineTooltipItem(
                  'Latency\n${spot.y.toStringAsFixed(1)} ms',
                  const TextStyle(
                    color: Color(0xFF9CC0FF),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              final loss = latencyScale <= 0
                  ? 0
                  : (spot.y / latencyScale) * lossScale;
              return LineTooltipItem(
                'Packet loss\n${loss.toStringAsFixed(1)}%',
                const TextStyle(
                  color: Color(0xFFFFC965),
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: latencySpots,
            isCurved: false,
            color: const Color(0xFF5E9CFF),
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF5E9CFF).withOpacity(0.12),
            ),
          ),
          LineChartBarData(
            spots: [
              for (final spot in lossSpots)
                FlSpot(
                  spot.x,
                  lossScale <= 0
                      ? 0
                      : (spot.y / lossScale) * latencyScale,
                ),
            ],
            isCurved: false,
            color: const Color(0xFFFFB020),
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Collecting gateway samples…',
        style: TextStyle(color: Color(0xFF8199B2)),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
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
        Text(label, style: Theme.of(context).textTheme.labelMedium),
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
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

double _niceScale(
  double peak, {
  required double minimum,
  double? maximum,
}) {
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
  final result = math.max(minimum, niceFraction * exponent);
  return maximum == null ? result : math.min(maximum, result);
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  return '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
