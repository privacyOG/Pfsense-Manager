part of 'network_monitor_screen.dart';

class _InterfaceTrafficCard extends StatelessWidget {
  const _InterfaceTrafficCard({
    required this.interface,
    required this.rates,
    required this.history,
    required this.accent,
    required this.unit,
  });

  final InterfaceStatus interface;
  final _InterfaceRates? rates;
  final List<_RateSample> history;
  final Color accent;
  final _BandwidthUnit unit;

  @override
  Widget build(BuildContext context) {
    final label = _interfaceLabel(interface);
    final inRate = rates?.inBps ?? 0;
    final outRate = rates?.outBps ?? 0;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.surfaceContainer,
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    interface.up ? Icons.link : Icons.link_off,
                    color: interface.up ? accent : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        interface.up ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: interface.up ? accent : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'IN  ${_formatRate(inRate, unit)}',
                      style: const TextStyle(
                        color: Color(0xFF29B6F6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'OUT  ${_formatRate(outRate, unit)}',
                      style: const TextStyle(
                        color: Color(0xFFFF8A00),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            InterfaceCounterRow(interface: interface),
            const SizedBox(height: 14),
            SizedBox(
              height: 170,
              child: _BandwidthChart(
                history: history,
                unit: unit,
                inboundColor: accent,
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficChartCard extends StatelessWidget {
  const _TrafficChartCard({
    required this.title,
    required this.subtitle,
    required this.history,
    required this.height,
    required this.unit,
  });

  final String title;
  final String subtitle;
  final List<_RateSample> history;
  final double height;
  final _BandwidthUnit unit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.surfaceContainerHigh,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            '$subtitle • ${unit == _BandwidthUnit.bits ? 'Bits/s' : 'Bytes/s'}',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const _ChartLegend(),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            child: _BandwidthChart(
              history: history,
              unit: unit,
              inboundColor: const Color(0xFF29B6F6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        _LegendItem(label: 'Inbound', color: Color(0xFF29B6F6)),
        _LegendItem(label: 'Outbound', color: Color(0xFFFF8A00)),
      ],
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
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
