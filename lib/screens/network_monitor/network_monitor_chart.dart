part of 'network_monitor_screen.dart';

class _BandwidthChart extends StatefulWidget {
  const _BandwidthChart({
    required this.history,
    required this.unit,
    required this.inboundColor,
    this.compact = false,
  });

  final List<_RateSample> history;
  final _BandwidthUnit unit;
  final Color inboundColor;
  final bool compact;

  @override
  State<_BandwidthChart> createState() => _BandwidthChartState();
}

class _BandwidthChartState extends State<_BandwidthChart> {
  @override
  Widget build(BuildContext context) {
    if (widget.history.length < 2) {
      return _ChartPlaceholder(compact: widget.compact);
    }

    final inbound = <FlSpot>[];
    final outbound = <FlSpot>[];
    var visiblePeak = 0.0;
    for (var index = 0; index < widget.history.length; index++) {
      final inValue = _displayRate(widget.history[index].inBps, widget.unit);
      final outValue = _displayRate(widget.history[index].outBps, widget.unit);
      visiblePeak = math.max(visiblePeak, math.max(inValue, outValue));
      inbound.add(FlSpot(index.toDouble(), inValue));
      outbound.add(FlSpot(index.toDouble(), -outValue));
    }

    final scale = _niceScale(visiblePeak);
    final interval = scale / 2;
    final maxX = math.max(1, widget.history.length - 1).toDouble();
    final scheme = Theme.of(context).colorScheme;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: -scale,
        maxY: scale,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: !widget.compact,
          horizontalInterval: interval,
          verticalInterval: widget.compact ? 1 : math.max(1, maxX / 4),
          getDrawingHorizontalLine: (value) => FlLine(
            color: value == 0
                ? scheme.onSurface.withValues(alpha: 0.42)
                : scheme.onSurface.withValues(alpha: 0.10),
            strokeWidth: value == 0 ? 1.4 : 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: scheme.onSurface.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: widget.compact ? 48 : 62,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value.abs() < interval / 10) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '0',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    _formatAxis(value.abs(), widget.unit),
                    style: TextStyle(
                      color: value > 0
                          ? const Color(0xFF81D4FA)
                          : const Color(0xFFFFB74D),
                      fontSize: widget.compact ? 9 : 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: widget.compact ? 22 : 28,
              interval: math.max(1, maxX / 2),
              getTitlesWidget: (value, meta) {
                final index = value
                    .round()
                    .clamp(0, widget.history.length - 1)
                    .toInt();
                final isStart = index == 0;
                final isMiddle =
                    (index - (widget.history.length - 1) / 2).abs() <= 1;
                final isEnd = index == widget.history.length - 1;
                if (!isStart && !isMiddle && !isEnd) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formatClock(widget.history[index].capturedAt),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: widget.compact ? 9 : 10,
                      fontWeight:
                          isStart || isEnd ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            right: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: !widget.compact,
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((_) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                  strokeWidth: 1.5,
                  dashArray: [4, 3],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 4.5,
                      color: barData.color ?? scheme.primary,
                      strokeWidth: 2,
                      strokeColor: scheme.surface,
                    );
                  },
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.surfaceContainerHigh,
            tooltipRoundedRadius: 10,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipItems: (spots) {
              return List.generate(spots.length, (i) {
                final spot = spots[i];
                final idx = spot.spotIndex.clamp(0, widget.history.length - 1);
                final time = _formatClock(widget.history[idx].capturedAt);
                final label = spot.barIndex == 0 ? '↑ In' : '↓ Out';
                final value = _formatDisplayValue(spot.y.abs(), widget.unit);
                return LineTooltipItem(
                  i == 0 ? '$time\n$label  $value' : '$label  $value',
                  TextStyle(
                    color: spot.barIndex == 0
                        ? const Color(0xFF81D4FA)
                        : const Color(0xFFFFB74D),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.45,
                  ),
                );
              });
            },
          ),
        ),
        lineBarsData: [
          _lineData(
            inbound,
            widget.inboundColor,
            fillToZero: true,
            aboveZero: true,
          ),
          _lineData(
            outbound,
            const Color(0xFFFF8A00),
            fillToZero: true,
            aboveZero: false,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}

LineChartBarData _lineData(
  List<FlSpot> spots,
  Color color, {
  required bool fillToZero,
  required bool aboveZero,
}) {
  return LineChartBarData(
    spots: spots,
    isCurved: false,
    color: color,
    barWidth: 2.2,
    isStrokeCapRound: true,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(
      show: fillToZero && aboveZero,
      color: color.withValues(alpha: 0.28),
      cutOffY: 0,
      applyCutOffY: true,
    ),
    aboveBarData: BarAreaData(
      show: fillToZero && !aboveZero,
      color: color.withValues(alpha: 0.30),
      cutOffY: 0,
      applyCutOffY: true,
    ),
  );
}
