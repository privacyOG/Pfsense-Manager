import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dashboard.dart';
import '../models/network_state.dart';
import '../providers/session_provider.dart';

class NetworkMonitorScreen extends StatefulWidget {
  const NetworkMonitorScreen({super.key});

  @override
  State<NetworkMonitorScreen> createState() => _NetworkMonitorScreenState();
}

class _NetworkMonitorScreenState extends State<NetworkMonitorScreen> {
  static const _maxHistorySeconds = 180;

  final _search = TextEditingController();
  final Map<String, _InterfaceCounters> _lastInterfaceCounters = {};
  final List<_TrafficSample> _history = [];
  List<NetworkState> _states = [];
  List<InterfaceStatus> _interfaces = [];
  DateTime? _lastSampleAt;
  Object? _error;
  bool _loading = false;
  bool _live = true;
  int _refreshSeconds = 3;
  String _quickFilter = 'all';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _refreshSeconds), (_) {
      if (_live) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_states.isEmpty && !_loading) _load(showSpinner: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _error = 'Disconnected');
      return;
    }
    if (showSpinner) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        session.service!.getFirewallStates(limit: 500),
        session.service!.getInterfaceStatuses(),
      ]);
      final states = results[0] as List<NetworkState>;
      final interfaces = results[1] as List<InterfaceStatus>;
      if (!mounted) return;
      setState(() {
        _states = states;
        _interfaces = interfaces;
        _recordTrafficSample(interfaces);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted && showSpinner) setState(() => _loading = false);
    }
  }

  void _recordTrafficSample(List<InterfaceStatus> interfaces) {
    final now = DateTime.now();
    final elapsedSeconds = _lastSampleAt == null
        ? _refreshSeconds.toDouble()
        : math.max(
            .5,
            now.difference(_lastSampleAt!).inMilliseconds / 1000,
          );
    final rates = <String, _InterfaceRates>{};
    final counters = <String, _InterfaceCounters>{};

    for (final interface in interfaces) {
      final key = _interfaceLabel(interface);
      final current = _InterfaceCounters(
        bytesIn: interface.bytesIn,
        bytesOut: interface.bytesOut,
      );
      final previous = _lastInterfaceCounters[key];
      final inRate = previous == null
          ? 0.0
          : math.max(0, current.bytesIn - previous.bytesIn) / elapsedSeconds;
      final outRate = previous == null
          ? 0.0
          : math.max(0, current.bytesOut - previous.bytesOut) / elapsedSeconds;
      rates[key] = _InterfaceRates(inBps: inRate, outBps: outRate);
      counters[key] = current;
    }

    _lastSampleAt = now;
    _lastInterfaceCounters
      ..clear()
      ..addAll(counters);
    _history.add(_TrafficSample(capturedAt: now, rates: rates));
    final maxSamples =
        math.max(8, (_maxHistorySeconds / _refreshSeconds).ceil());
    while (_history.length > maxSamples) {
      _history.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = _states
        .where(_matchesQuickFilter)
        .where((state) =>
            q.isEmpty ||
            state.source.toLowerCase().contains(q) ||
            state.destination.toLowerCase().contains(q) ||
            state.interface.toLowerCase().contains(q) ||
            state.protocol.toLowerCase().contains(q) ||
            state.state.toLowerCase().contains(q))
        .toList();
    final bytes = _states.fold<int>(0, (sum, state) => sum + state.bytes);
    final packets = _states.fold<int>(0, (sum, state) => sum + state.packets);
    final interfaceTotals = _totalsByInterface(_states);
    final protocolTotals = _totalsByProtocol(_states);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _Header(
            stateCount: _states.length,
            bytes: bytes,
            packets: packets,
            live: _live,
            onLiveChanged: (value) => setState(() => _live = value),
            refreshSeconds: _refreshSeconds,
            onRefreshSecondsChanged: (value) {
              setState(() {
                _refreshSeconds = value;
                _history.clear();
                _lastInterfaceCounters.clear();
                _lastSampleAt = null;
              });
              _startTimer();
              if (_live) _load();
            },
          ),
          const SizedBox(height: 14),
          _InterfaceTrafficGraph(
            history: _history,
            interfaces: _interfaces,
            sampleSeconds: _refreshSeconds,
          ),
          const SizedBox(height: 14),
          _BreakdownPanel(
            interfaces: interfaceTotals,
            protocols: protocolTotals,
          ),
          const SizedBox(height: 14),
          _FilterChips(
            selected: _quickFilter,
            onChanged: (value) => setState(() => _quickFilter = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Filter IP, port, interface, protocol or state',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_error != null)
            _Message(icon: Icons.error_outline, text: '$_error'),
          if (!_loading && _error == null && visible.isEmpty)
            const _Message(
              icon: Icons.travel_explore,
              text: 'No live firewall states reported yet.',
            ),
          for (final state in visible.take(250)) _StateTile(state),
        ],
      ),
    );
  }

  Map<String, int> _totalsByInterface(List<NetworkState> states) {
    final totals = <String, int>{};
    for (final state in states) {
      final key = state.interface.isEmpty ? 'unknown' : state.interface;
      totals[key] = (totals[key] ?? 0) + state.bytes;
    }
    return totals;
  }

  Map<String, int> _totalsByProtocol(List<NetworkState> states) {
    final totals = <String, int>{};
    for (final state in states) {
      final key =
          state.protocol.isEmpty ? 'other' : state.protocol.toUpperCase();
      totals[key] = (totals[key] ?? 0) + 1;
    }
    return totals;
  }

  bool _matchesQuickFilter(NetworkState state) {
    final iface = state.interface.toLowerCase();
    final proto = state.protocol.toLowerCase();
    final stateText = state.state.toLowerCase();
    return switch (_quickFilter) {
      'wan' => iface.contains('wan'),
      'lan' => iface.contains('lan'),
      'vpn' => iface.contains('vpn') ||
          iface.contains('ovpn') ||
          iface.contains('ipsec'),
      'tcp' => proto.contains('tcp'),
      'udp' => proto.contains('udp'),
      'established' =>
        stateText.contains('estab') || stateText.contains('syn_sent'),
      _ => true,
    };
  }
}

String _interfaceLabel(InterfaceStatus interface) {
  final description = interface.description.trim();
  if (description.isNotEmpty) return description;
  final name = interface.name.trim();
  if (name.isNotEmpty) return name.toUpperCase();
  return interface.hardwareInterface.trim().isEmpty
      ? 'unknown'
      : interface.hardwareInterface;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.stateCount,
    required this.bytes,
    required this.packets,
    required this.live,
    required this.onLiveChanged,
    required this.refreshSeconds,
    required this.onRefreshSecondsChanged,
  });

  final int stateCount;
  final int bytes;
  final int packets;
  final bool live;
  final ValueChanged<bool> onLiveChanged;
  final int refreshSeconds;
  final ValueChanged<int> onRefreshSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Color(0xFF5E9CFF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Real-time Network Activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Switch(value: live, onChanged: onLiveChanged),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              Text('Refresh', style: Theme.of(context).textTheme.labelLarge),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1s')),
                  ButtonSegment(value: 3, label: Text('3s')),
                  ButtonSegment(value: 5, label: Text('5s')),
                  ButtonSegment(value: 10, label: Text('10s')),
                ],
                selected: {refreshSeconds},
                onSelectionChanged: (values) =>
                    onRefreshSecondsChanged(values.first),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat('States', _formatCount(stateCount)),
              _Stat('Traffic', _formatBytes(bytes)),
              _Stat('Packets', _formatCount(packets)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InterfaceTrafficGraph extends StatelessWidget {
  const _InterfaceTrafficGraph({
    required this.history,
    required this.interfaces,
    required this.sampleSeconds,
  });

  final List<_TrafficSample> history;
  final List<InterfaceStatus> interfaces;
  final int sampleSeconds;

  @override
  Widget build(BuildContext context) {
    final labels = interfaces.map(_interfaceLabel).toList();
    return Column(
      children: [
        if (labels.isEmpty)
          const Card(
            child: SizedBox(
              height: 180,
              child: Center(child: Text('Waiting for interface traffic')),
            ),
          )
        else
          for (final label in labels)
            _SingleInterfaceTrafficChart(
              label: label,
              history: history,
              sampleSeconds: sampleSeconds,
            ),
      ],
    );
  }
}

class _SingleInterfaceTrafficChart extends StatelessWidget {
  const _SingleInterfaceTrafficChart({
    required this.label,
    required this.history,
    required this.sampleSeconds,
  });

  final String label;
  final List<_TrafficSample> history;
  final int sampleSeconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const inColor = Color(0xFF1388B8);
    const outColor = Color(0xFFFF7A18);
    final rates = [
      for (final sample in history)
        sample.rates[label] ?? const _InterfaceRates(inBps: 0, outBps: 0),
    ];
    final maxRate = rates.fold<double>(
      1,
      (max, rate) => math.max(max, math.max(rate.inBps, rate.outBps)),
    );
    final scale = _TrafficScale.forBytesPerSecond(maxRate);
    final maxY = scale.maxChartValue;
    final maxX = math.max(1, (history.length - 1) * sampleSeconds).toDouble();
    final verticalInterval = _secondsAxisInterval(maxX);
    final latest =
        rates.isEmpty ? const _InterfaceRates(inBps: 0, outBps: 0) : rates.last;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _LegendChip(
                  color: inColor,
                  label: '$label (in) ${_formatRate(latest.inBps)}',
                ),
                _LegendChip(
                  color: outColor,
                  label: '$label (out) ${_formatRate(latest.outBps)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: -maxY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: scale.interval,
                    verticalInterval: verticalInterval,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: value == 0
                          ? scheme.outline.withValues(alpha: .55)
                          : scheme.outlineVariant.withValues(alpha: .45),
                      strokeWidth: value == 0 ? 1.3 : 1,
                    ),
                    getDrawingVerticalLine: (_) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: .45),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      right: BorderSide(color: scheme.outline),
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 54,
                        interval: scale.interval,
                        getTitlesWidget: (value, meta) {
                          if ((value / scale.interval).roundToDouble() !=
                              value / scale.interval) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              scale.format(value),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: verticalInterval,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value > maxX) {
                            return const SizedBox.shrink();
                          }
                          final remaining = (maxX - value).round();
                          return Text(
                            remaining == 0 ? 'now' : '-${remaining}s',
                            style: Theme.of(context).textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            '${spot.barIndex == 0 ? 'In' : 'Out'} ${scale.format(spot.y)}',
                            TextStyle(
                              color: spot.barIndex == 0 ? inColor : outColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var x = 0; x < rates.length; x++)
                          FlSpot(
                            (x * sampleSeconds).toDouble(),
                            rates[x].inBps / scale.divisor,
                          ),
                      ],
                      isCurved: false,
                      barWidth: 3,
                      color: inColor,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: inColor.withValues(alpha: .45),
                        cutOffY: 0,
                        applyCutOffY: true,
                      ),
                    ),
                    LineChartBarData(
                      spots: [
                        for (var x = 0; x < rates.length; x++)
                          FlSpot(
                            (x * sampleSeconds).toDouble(),
                            -rates[x].outBps / scale.divisor,
                          ),
                      ],
                      isCurved: false,
                      barWidth: 3,
                      color: outColor,
                      dotData: const FlDotData(show: false),
                      aboveBarData: BarAreaData(
                        show: true,
                        color: outColor.withValues(alpha: .42),
                        cutOffY: 0,
                        applyCutOffY: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'All', Icons.all_inclusive),
      ('wan', 'WAN', Icons.cloud_outlined),
      ('lan', 'LAN', Icons.lan_outlined),
      ('vpn', 'VPN', Icons.vpn_lock_outlined),
      ('tcp', 'TCP', Icons.swap_horiz),
      ('udp', 'UDP', Icons.bolt_outlined),
      ('established', 'Active', Icons.play_circle_outline),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          FilterChip(
            selected: selected == filter.$1,
            avatar: Icon(filter.$3, size: 18),
            label: Text(filter.$2),
            onSelected: (_) => onChanged(filter.$1),
          ),
      ],
    );
  }
}

class _BreakdownPanel extends StatelessWidget {
  const _BreakdownPanel({required this.interfaces, required this.protocols});

  final Map<String, int> interfaces;
  final Map<String, int> protocols;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final children = [
          _BreakdownCard(
            icon: Icons.settings_ethernet,
            title: 'Interface totals',
            values: interfaces,
            formatter: _formatBytes,
          ),
          _BreakdownCard(
            icon: Icons.account_tree_outlined,
            title: 'Protocol mix',
            values: protocols,
            formatter: _formatCount,
          ),
        ];
        return wide
            ? Row(children: [
                for (final child in children) Expanded(child: child),
              ])
            : Column(children: children);
      },
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.icon,
    required this.title,
    required this.values,
    required this.formatter,
  });

  final IconData icon;
  final String title;
  final Map<String, int> values;
  final String Function(int) formatter;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = sorted.isEmpty ? 1 : sorted.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              const Text('No data yet')
            else
              for (final entry in sorted.take(5)) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.key,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(formatter(entry.value)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: entry.value / maxValue,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile(this.state);

  final NetworkState state;

  @override
  Widget build(BuildContext context) {
    final color = _protocolColor(state.protocol);
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Icon(Icons.timeline, color: color),
        ),
        title: Text(
          '${state.source} -> ${state.destination}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            state.protocol.toUpperCase(),
            if (state.interface.isNotEmpty) state.interface,
            if (state.state.isNotEmpty) state.state,
          ].join('  |  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatBytes(state.bytes)),
            Text(
              '${_formatCount(state.packets)} pkts',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          _DetailGrid(items: {
            'Source IP': state.sourceIp,
            'Source port': state.sourcePort.isEmpty ? 'n/a' : state.sourcePort,
            'Destination IP': state.destinationIp,
            'Destination port':
                state.destinationPort.isEmpty ? 'n/a' : state.destinationPort,
            'Protocol': state.protocol.toUpperCase(),
            'Interface': state.interface.isEmpty ? 'unknown' : state.interface,
            'State': state.state.isEmpty ? 'n/a' : state.state,
            'Age': state.age.isEmpty ? 'n/a' : state.age,
            'Expires': state.expires.isEmpty ? 'n/a' : state.expires,
            'Data': _formatBytes(state.bytes),
            'Packets': _formatCount(state.packets),
          }),
        ],
      ),
    );
  }

  Color _protocolColor(String protocol) {
    final p = protocol.toLowerCase();
    if (p.contains('tcp')) return const Color(0xFF5E9CFF);
    if (p.contains('udp')) return const Color(0xFF00C2A8);
    if (p.contains('icmp')) return const Color(0xFFFFB020);
    return Colors.grey;
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});

  final Map<String, String> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 3 : 2;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 3 ? 3.6 : 2.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final entry in items.entries)
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(entry.key,
                        style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(leading: Icon(icon), title: Text(text)));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _TrafficSample {
  const _TrafficSample({required this.capturedAt, required this.rates});

  final DateTime capturedAt;
  final Map<String, _InterfaceRates> rates;
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

class _TrafficScale {
  const _TrafficScale({
    required this.divisor,
    required this.suffix,
    required this.interval,
    required this.maxChartValue,
  });

  final double divisor;
  final String suffix;
  final double interval;
  final double maxChartValue;

  factory _TrafficScale.forBytesPerSecond(double bytesPerSecond) {
    const kib = 1024.0;
    const mib = 1024.0 * 1024.0;
    final mbps = bytesPerSecond / mib;
    if (mbps >= 10) {
      return _TrafficScale(
        divisor: mib,
        suffix: 'M',
        interval: 10,
        maxChartValue: math.max(10, (mbps / 10).ceil() * 10).toDouble(),
      );
    }
    if (mbps >= 1) {
      return _TrafficScale(
        divisor: mib,
        suffix: 'M',
        interval: 1,
        maxChartValue: math.max(1, mbps.ceil()).toDouble(),
      );
    }
    final kbps = bytesPerSecond / kib;
    if (kbps >= 100) {
      return _TrafficScale(
        divisor: kib,
        suffix: 'k',
        interval: 100,
        maxChartValue: math.max(100, (kbps / 100).ceil() * 100).toDouble(),
      );
    }
    return _TrafficScale(
      divisor: kib,
      suffix: 'k',
      interval: 10,
      maxChartValue: math.max(10, (kbps / 10).ceil() * 10).toDouble(),
    );
  }

  String format(double value) {
    if (value == 0) return '0.0';
    final sign = value < 0 ? '-' : '';
    final absValue = value.abs();
    final digits = absValue >= 10 ? 0 : 1;
    return '$sign${absValue.toStringAsFixed(digits)}$suffix';
  }
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatRate(num bytesPerSecond) => '${_formatBytes(bytesPerSecond)}/s';

double _secondsAxisInterval(double maxSeconds) {
  if (maxSeconds <= 30) return 5;
  if (maxSeconds <= 90) return 15;
  if (maxSeconds <= 180) return 30;
  return 60;
}

String _formatCount(int value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
