import 'package:flutter/material.dart';

import '../models/dashboard.dart';

class InterfaceTrafficTotals extends StatelessWidget {
  const InterfaceTrafficTotals({
    super.key,
    required this.interfaces,
  });

  final List<InterfaceStatus> interfaces;

  @override
  Widget build(BuildContext context) {
    final bytesIn = interfaces.fold<int>(0, (sum, item) => sum + item.bytesIn);
    final bytesOut = interfaces.fold<int>(0, (sum, item) => sum + item.bytesOut);
    final packetsIn = interfaces.fold<int>(0, (sum, item) => sum + item.packetsIn);
    final packetsOut = interfaces.fold<int>(0, (sum, item) => sum + item.packetsOut);
    final errorsIn = interfaces.fold<int>(0, (sum, item) => sum + item.errorsIn);
    final errorsOut = interfaces.fold<int>(0, (sum, item) => sum + item.errorsOut);
    final collisions = interfaces.fold<int>(0, (sum, item) => sum + item.collisions);

    final items = [
      _Counter('Bytes in', _formatBytes(bytesIn), Icons.south_west, const Color(0xFF29B6F6)),
      _Counter('Bytes out', _formatBytes(bytesOut), Icons.north_east, const Color(0xFFFF8A00)),
      _Counter('Packets in', _formatCount(packetsIn), Icons.download_outlined, const Color(0xFF66BB6A)),
      _Counter('Packets out', _formatCount(packetsOut), Icons.upload_outlined, const Color(0xFFAB47BC)),
      _Counter('Input errors', _formatCount(errorsIn), Icons.error_outline, _healthColor(errorsIn)),
      _Counter('Output errors', _formatCount(errorsOut), Icons.report_problem_outlined, _healthColor(errorsOut)),
      _Counter('Collisions', _formatCount(collisions), Icons.call_merge, _healthColor(collisions)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 420
                ? 2
                : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(width: width, child: _CounterTile(counter: item)),
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
  const _CounterTile({required this.counter});

  final _Counter counter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: counter.color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Icon(counter.icon, color: counter.color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  counter.label,
                  style: const TextStyle(color: Color(0xFFAFC0D1), fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  counter.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: counter.color,
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
    final color = alert ? Colors.orangeAccent : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: alert
            ? Colors.orangeAccent.withOpacity(0.10)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: alert
            ? Border.all(color: Colors.orangeAccent.withOpacity(0.35))
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9CB3CA), fontSize: 10)),
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
  return value > 0 ? Colors.orangeAccent : const Color(0xFF00C2A8);
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
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _formatCount(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
