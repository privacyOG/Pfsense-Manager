import 'package:flutter/material.dart';

import '../models/dashboard.dart';

class InterfaceTrafficTotals extends StatelessWidget {
  const InterfaceTrafficTotals({
    super.key,
    required this.interfaces,
    this.compact = false,
    this.darkSurface = false,
  });

  final List<InterfaceStatus> interfaces;
  final bool compact;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    final bytesIn = interfaces.fold<int>(0, (sum, item) => sum + item.bytesIn);
    final bytesOut = interfaces.fold<int>(0, (sum, item) => sum + item.bytesOut);
    final packetsIn = interfaces.fold<int>(0, (sum, item) => sum + item.packetsIn);
    final packetsOut = interfaces.fold<int>(0, (sum, item) => sum + item.packetsOut);
    final errorsIn = interfaces.fold<int>(0, (sum, item) => sum + item.errorsIn);
    final errorsOut = interfaces.fold<int>(0, (sum, item) => sum + item.errorsOut);
    final collisions = interfaces.fold<int>(0, (sum, item) => sum + item.collisions);

    const inboundColor = Color(0xFF29B6F6);
    const outboundColor = Color(0xFFFF9D2E);

    final trafficItems = [
      _Counter('Bytes in', _formatBytes(bytesIn), Icons.south_west, inboundColor),
      _Counter(
        'Bytes out',
        _formatBytes(bytesOut),
        Icons.north_east,
        outboundColor,
      ),
      _Counter(
        'Packets in',
        _formatCount(packetsIn),
        Icons.download_outlined,
        inboundColor,
      ),
      _Counter(
        'Packets out',
        _formatCount(packetsOut),
        Icons.upload_outlined,
        outboundColor,
      ),
    ];

    final healthItems = [
      _Counter(
        'Input errors',
        _formatCount(errorsIn),
        Icons.error_outline,
        _healthColor(errorsIn),
      ),
      _Counter(
        'Output errors',
        _formatCount(errorsOut),
        Icons.report_problem_outlined,
        _healthColor(errorsOut),
      ),
      _Counter(
        'Collisions',
        _formatCount(collisions),
        Icons.call_merge,
        _healthColor(collisions),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CounterGrid(
          counters: compact ? trafficItems : [...trafficItems, ...healthItems],
          compact: compact,
          darkSurface: darkSurface,
        ),
        if (compact) ...[
          const SizedBox(height: 8),
          _HealthSummary(
            errors: errorsIn + errorsOut,
            collisions: collisions,
            darkSurface: darkSurface,
          ),
        ],
      ],
    );
  }
}

class _CounterGrid extends StatelessWidget {
  const _CounterGrid({
    required this.counters,
    required this.compact,
    required this.darkSurface,
  });

  final List<_Counter> counters;
  final bool compact;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 300
                ? 2
                : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final counter in counters)
              SizedBox(
                width: width,
                child: _CounterTile(
                  counter: counter,
                  compact: compact,
                  darkSurface: darkSurface,
                ),
              ),
          ],
        );
      },
    );
  }
}

class InterfaceCounterRow extends StatelessWidget {
  const InterfaceCounterRow({super.key, required this.interface});

  final InterfaceStatus interface;

  @override
  Widget build(BuildContext context) {
    final children = [
      _InlineCounter(label: 'Bytes in', value: _formatBytes(interface.bytesIn)),
      _InlineCounter(label: 'Bytes out', value: _formatBytes(interface.bytesOut)),
      _InlineCounter(label: 'Packets in', value: _formatCount(interface.packetsIn)),
      _InlineCounter(label: 'Packets out', value: _formatCount(interface.packetsOut)),
      _InlineCounter(
        label: 'Input errors',
        value: _formatCount(interface.errorsIn),
        alert: interface.errorsIn > 0,
      ),
      _InlineCounter(
        label: 'Output errors',
        value: _formatCount(interface.errorsOut),
        alert: interface.errorsOut > 0,
      ),
      _InlineCounter(
        label: 'Collisions',
        value: _formatCount(interface.collisions),
        alert: interface.collisions > 0,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: constraints.maxWidth < 430 ? 2 : 4,
          childAspectRatio: constraints.maxWidth < 430 ? 2.2 : 1.8,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _Counter {
  const _Counter(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.counter,
    required this.compact,
    required this.darkSurface,
  });

  final _Counter counter;
  final bool compact;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = darkSurface
        ? const Color(0xFF1D3345)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final labelColor =
        darkSurface ? const Color(0xFFA9B8C7) : scheme.onSurfaceVariant;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 68 : 0),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 11,
        vertical: compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: counter.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(counter.icon, color: counter.color, size: compact ? 18 : 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  counter.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: compact ? 11 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  counter.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: counter.color,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 14 : null,
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

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({
    required this.errors,
    required this.collisions,
    required this.darkSurface,
  });

  final int errors;
  final int collisions;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    final healthy = errors == 0 && collisions == 0;
    final scheme = Theme.of(context).colorScheme;
    final color = healthy ? const Color(0xFF66BB6A) : Colors.orangeAccent;
    final background = darkSurface
        ? const Color(0xFF1D3345)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.42);
    final text = healthy
        ? 'No interface errors reported'
        : '${_pluralise(errors, 'error')} • '
            '${_pluralise(collisions, 'collision')}';

    return Container(
      key: const Key('interface-health-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: darkSurface ? const Color(0xFFA9B8C7) : scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineCounter extends StatelessWidget {
  const _InlineCounter({
    required this.label,
    required this.value,
    this.alert = false,
  });

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = alert ? Colors.orangeAccent : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: alert
            ? Colors.orangeAccent.withValues(alpha: 0.10)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: alert
            ? Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35))
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

Color _healthColor(int value) {
  return value > 0 ? Colors.orangeAccent : const Color(0xFF66BB6A);
}

String _pluralise(int value, String singular) {
  return '$value ${value == 1 ? singular : '${singular}s'}';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
  }
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} kB';
  }
  return '$bytes B';
}

String _formatCount(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
