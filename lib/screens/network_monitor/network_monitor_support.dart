part of 'network_monitor_screen.dart';

double _displayRate(double bytesPerSecond, _BandwidthUnit unit) {
  return unit == _BandwidthUnit.bits ? bytesPerSecond * 8 : bytesPerSecond;
}

double _niceScale(double peak) {
  if (!peak.isFinite || peak <= 0) return 1;
  final padded = peak * 1.18;
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
  return math.max(1, niceFraction * exponent);
}

String _formatRate(double bytesPerSecond, _BandwidthUnit unit) {
  return networkMonitorFormatRate(
    bytesPerSecond,
    bits: unit == _BandwidthUnit.bits,
  );
}

String _formatDisplayValue(double value, _BandwidthUnit unit) {
  final base = unit == _BandwidthUnit.bits ? 1000.0 : 1024.0;
  final suffixes = unit == _BandwidthUnit.bits
      ? const ['b/s', 'kb/s', 'Mb/s', 'Gb/s', 'Tb/s']
      : const ['B/s', 'kB/s', 'MB/s', 'GB/s', 'TB/s'];

  var scaled = value.abs();
  var suffixIndex = 0;
  while (scaled >= base && suffixIndex < suffixes.length - 1) {
    scaled /= base;
    suffixIndex++;
  }
  final decimals = scaled >= 100
      ? 0
      : scaled >= 10
          ? 1
          : 2;
  return '${scaled.toStringAsFixed(decimals)} ${suffixes[suffixIndex]}';
}

String _formatAxis(double value, _BandwidthUnit unit) {
  final formatted = _formatDisplayValue(value, unit);
  return formatted.replaceAll('/s', '');
}

String _formatClock(DateTime value) {
  final local = value.toLocal();
  return '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

String _interfaceLabel(InterfaceStatus interface) {
  final description = interface.description.trim();
  if (description.isNotEmpty) return description;
  final name = interface.name.trim();
  if (name.isNotEmpty) return name.toUpperCase();
  final hardware = interface.hardwareInterface.trim();
  return hardware.isEmpty ? 'unknown' : hardware;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        compact
            ? 'Collecting traffic samples…'
            : 'Live chart starts after the next sample',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1D3345),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFA9B8C7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE6EDF5),
                    fontWeight: FontWeight.w800,
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

class _InterfaceCounters {
  const _InterfaceCounters({required this.bytesIn, required this.bytesOut});

  final int bytesIn;
  final int bytesOut;
}

class _InterfaceRates {
  const _InterfaceRates({required this.inBps, required this.outBps});

  final double inBps;
  final double outBps;
}

class _RateSample {
  const _RateSample({
    required this.capturedAt,
    required this.inBps,
    required this.outBps,
  });

  final DateTime capturedAt;
  final double inBps;
  final double outBps;
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(text),
      ),
    );
  }
}
