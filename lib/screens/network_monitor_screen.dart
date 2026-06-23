import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../models/network_state.dart';
import '../providers/session_provider.dart';
import '../widgets/interface_traffic_totals.dart';

enum _BandwidthUnit { bytes, bits }

class NetworkMonitorScreen extends StatefulWidget {
  const NetworkMonitorScreen({super.key});

  @override
  State<NetworkMonitorScreen> createState() => _NetworkMonitorScreenState();
}

class _NetworkMonitorScreenState extends State<NetworkMonitorScreen>
    with WidgetsBindingObserver {
  static const _minimumRefreshSeconds = 1;
  static const _historyWindowSeconds = 120;
  static const _prefLive = 'networkMonitor.live';
  static const _prefRefreshSeconds = 'networkMonitor.refreshSeconds';
  static const _prefQuickFilter = 'networkMonitor.quickFilter';
  static const _prefBandwidthUnit = 'networkMonitor.bandwidthUnit';

  final _search = TextEditingController();
  final Map<String, _InterfaceCounters> _previousCounters = {};
  final Map<String, _InterfaceRates> _rates = {};
  final Map<String, List<_RateSample>> _interfaceHistory = {};
  final List<_RateSample> _totalHistory = [];

  List<NetworkState> _states = [];
  List<InterfaceStatus> _interfaces = [];
  Object? _error;
  bool _loading = false;
  bool _live = true;
  bool _appActive = true;
  bool _preferencesLoaded = false;
  int _refreshSeconds = 3;
  String _quickFilter = 'all';
  _BandwidthUnit _bandwidthUnit = _BandwidthUnit.bits;
  Timer? _timer;
  DateTime? _lastSampleAt;
  DateTime? _lastSuccessfulRefresh;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedInterval = preferences.getInt(_prefRefreshSeconds) ?? 3;
    final allowedIntervals = const {1, 3, 5, 10};
    final savedUnit = preferences.getString(_prefBandwidthUnit);
    setState(() {
      _live = preferences.getBool(_prefLive) ?? true;
      _refreshSeconds = allowedIntervals.contains(savedInterval)
          ? savedInterval
          : math.max(_minimumRefreshSeconds, savedInterval);
      _quickFilter = preferences.getString(_prefQuickFilter) ?? 'all';
      _bandwidthUnit =
          savedUnit == 'bytes' ? _BandwidthUnit.bytes : _BandwidthUnit.bits;
      _preferencesLoaded = true;
    });
    _startTimer();
  }

  Future<void> _savePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_prefLive, _live);
    await preferences.setInt(_prefRefreshSeconds, _refreshSeconds);
    await preferences.setString(_prefQuickFilter, _quickFilter);
    await preferences.setString(
      _prefBandwidthUnit,
      _bandwidthUnit == _BandwidthUnit.bytes ? 'bytes' : 'bits',
    );
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    if (active && _live && mounted) {
      _load();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_preferencesLoaded) return;
    final interval = math.max(_minimumRefreshSeconds, _refreshSeconds);
    _timer = Timer.periodic(Duration(seconds: interval), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_live &&
          _appActive &&
          session.connected &&
          session.service != null &&
          !_loading) {
        _load();
      }
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
      _clearLiveData();
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_states.isEmpty && session.connected && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  void _clearLiveData() {
    _states = [];
    _interfaces = [];
    _previousCounters.clear();
    _rates.clear();
    _interfaceHistory.clear();
    _totalHistory.clear();
    _lastSampleAt = null;
    _lastSuccessfulRefresh = null;
    _error = null;
  }

  @override
  void dispose() {
    _requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _clearLiveData();
        _error = 'Disconnected';
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });

    try {
      final results = await Future.wait([
        session.service!.getFirewallStates(limit: 500),
        session.service!.getInterfaceStatuses(),
      ]);
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }

      final states = results[0] as List<NetworkState>;
      final interfaces = results[1] as List<InterfaceStatus>;
      _recordRates(interfaces);
      setState(() {
        _states = states;
        _interfaces = interfaces;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _recordRates(List<InterfaceStatus> interfaces) {
    final now = DateTime.now();
    final elapsed = _lastSampleAt == null
        ? _refreshSeconds.toDouble()
        : math.max(
            0.5,
            now.difference(_lastSampleAt!).inMilliseconds / 1000,
          );
    final nextCounters = <String, _InterfaceCounters>{};
    final nextRates = <String, _InterfaceRates>{};
    var totalIn = 0.0;
    var totalOut = 0.0;

    for (final interface in interfaces) {
      final key = _interfaceLabel(interface);
      final current = _InterfaceCounters(
        bytesIn: interface.bytesIn,
        bytesOut: interface.bytesOut,
      );
      final previous = _previousCounters[key];
      final inRate = previous == null
          ? 0.0
          : math.max(0, current.bytesIn - previous.bytesIn) / elapsed;
      final outRate = previous == null
          ? 0.0
          : math.max(0, current.bytesOut - previous.bytesOut) / elapsed;

      nextCounters[key] = current;
      nextRates[key] = _InterfaceRates(inBps: inRate, outBps: outRate);
      totalIn += inRate;
      totalOut += outRate;

      final history = _interfaceHistory.putIfAbsent(key, () => []);
      history.add(
        _RateSample(capturedAt: now, inBps: inRate, outBps: outRate),
      );
      _trimHistory(history, now);
    }

    _totalHistory.add(
      _RateSample(capturedAt: now, inBps: totalIn, outBps: totalOut),
    );
    _trimHistory(_totalHistory, now);

    _previousCounters
      ..clear()
      ..addAll(nextCounters);
    _rates
      ..clear()
      ..addAll(nextRates);
    _lastSampleAt = now;
  }

  void _trimHistory(List<_RateSample> history, DateTime now) {
    final cutoff = now.subtract(const Duration(seconds: _historyWindowSeconds));
    history.removeWhere((sample) => sample.capturedAt.isBefore(cutoff));
    final maxSamples =
        math.max(12, (_historyWindowSeconds / _refreshSeconds).ceil() + 2);
    if (history.length > maxSamples) {
      history.removeRange(0, history.length - maxSamples);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final query = _search.text.trim().toLowerCase();
    final visible = _states
        .where(_matchesQuickFilter)
        .where((state) {
          if (query.isEmpty) return true;
          return [
            state.source,
            state.destination,
            state.interface,
            state.protocol,
            state.state,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList();

    final totalRates = _totalHistory.isEmpty
        ? const _InterfaceRates(inBps: 0, outBps: 0)
        : _InterfaceRates(
            inBps: _totalHistory.last.inBps,
            outBps: _totalHistory.last.outBps,
          );

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _summaryCard(rates: totalRates),
          const SizedBox(height: 14),
          _TrafficChartCard(
            title: 'Live throughput',
            subtitle: 'Combined traffic across all reported interfaces',
            history: _totalHistory,
            height: 250,
            unit: _bandwidthUnit,
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${_formatClock(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const _Message(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            _Message(icon: Icons.error_outline, text: _error.toString()),
          if (session.connected && _interfaces.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Interface traffic',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _interfaces.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InterfaceTrafficCard(
                  interface: _interfaces[index],
                  rates: _rates[_interfaceLabel(_interfaces[index])],
                  history:
                      _interfaceHistory[_interfaceLabel(_interfaces[index])] ??
                          const [],
                  accent: _interfaceAccent(index),
                  unit: _bandwidthUnit,
                ),
              ),
          ],
          const SizedBox(height: 4),
          _filterControls(),
          const SizedBox(height: 12),
          if (session.connected && !_loading && visible.isEmpty)
            const _Message(
              icon: Icons.travel_explore,
              text: 'No live firewall states reported yet.',
            ),
          if (session.connected)
            for (final state in visible.take(250)) _stateTile(state),
        ],
      ),
    );
  }

  Widget _summaryCard({required _InterfaceRates rates}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primaryContainer, colorScheme.primary.withValues(alpha: 0.85)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Real-time Network Activity',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              Switch(
                value: _live,
                onChanged: (value) {
                  setState(() => _live = value);
                  _savePreferences();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<_BandwidthUnit>(
            segments: const [
              ButtonSegment(
                value: _BandwidthUnit.bits,
                label: Text('bits/s'),
              ),
              ButtonSegment(
                value: _BandwidthUnit.bytes,
                label: Text('Bytes/s'),
              ),
            ],
            selected: {_bandwidthUnit},
            onSelectionChanged: (values) {
              setState(() => _bandwidthUnit = values.first);
              _savePreferences();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Inbound',
                  value: _formatRate(rates.inBps, _bandwidthUnit),
                  icon: Icons.south_west,
                  color: const Color(0xFF29B6F6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Outbound',
                  value: _formatRate(rates.outBps, _bandwidthUnit),
                  icon: Icons.north_east,
                  color: const Color(0xFFFF8A00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InterfaceTrafficTotals(interfaces: _interfaces),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1s')),
              ButtonSegment(value: 3, label: Text('3s')),
              ButtonSegment(value: 5, label: Text('5s')),
              ButtonSegment(value: 10, label: Text('10s')),
            ],
            selected: {_refreshSeconds},
            onSelectionChanged: (values) {
              final value = values.first;
              setState(() {
                _refreshSeconds = math.max(_minimumRefreshSeconds, value);
                _previousCounters.clear();
                _rates.clear();
                _interfaceHistory.clear();
                _totalHistory.clear();
                _lastSampleAt = null;
              });
              _startTimer();
              _savePreferences();
              if (_live) _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _filterControls() {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const [
              'all',
              'wan',
              'lan',
              'vpn',
              'tcp',
              'udp',
              'established',
            ])
              ChoiceChip(
                label: Text(value.toUpperCase()),
                selected: _quickFilter == value,
                onSelected: (_) {
                  setState(() => _quickFilter = value);
                  _savePreferences();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Filter IP, interface, protocol or state',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ],
    );
  }

  Widget _stateTile(NetworkState state) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text('${state.source} → ${state.destination}'),
        subtitle: Text(
          '${state.interface} • ${state.protocol.toUpperCase()} • ${state.state}',
        ),
        trailing: Text(_formatBytes(state.bytes)),
      ),
    );
  }

  bool _matchesQuickFilter(NetworkState state) {
    final interface = state.interface.toLowerCase();
    final protocol = state.protocol.toLowerCase();
    final status = state.state.toLowerCase();
    return switch (_quickFilter) {
      'wan' => interface.contains('wan'),
      'lan' => interface.contains('lan'),
      'vpn' => interface.contains('vpn') ||
          interface.contains('ovpn') ||
          interface.contains('ipsec'),
      'tcp' => protocol.contains('tcp'),
      'udp' => protocol.contains('udp'),
      'established' =>
        status.contains('estab') || status.contains('syn_sent'),
      _ => true,
    };
  }

  Color _interfaceAccent(int index) {
    const accents = [
      Color(0xFF29B6F6),
      Color(0xFF66BB6A),
      Color(0xFFAB47BC),
      Color(0xFFFFCA28),
      Color(0xFF26C6DA),
      Color(0xFFEF5350),
    ];
    return accents[index % accents.length];
  }
}

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
            '$subtitle • ${unit == _BandwidthUnit.bits ? 'bits/s' : 'Bytes/s'}',
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
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

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
                  return const Padding(
                    padding: EdgeInsets.only(left: 6),
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
                final index =
                    value.round().clamp(0, widget.history.length - 1).toInt();
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
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
                      color: barData.color ?? Colors.white,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    );
                  },
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0E2844),
            tooltipRoundedRadius: 10,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipItems: (spots) {
              return List.generate(spots.length, (i) {
                final spot = spots[i];
                final idx =
                    spot.spotIndex.clamp(0, widget.history.length - 1);
                final time = _formatClock(widget.history[idx].capturedAt);
                final label = spot.barIndex == 0 ? '↑ In' : '↓ Out';
                final value =
                    _formatDisplayValue(spot.y.abs(), widget.unit);
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
  return _formatDisplayValue(_displayRate(bytesPerSecond, unit), unit);
}

String _formatDisplayValue(double value, _BandwidthUnit unit) {
  final base = unit == _BandwidthUnit.bits ? 1000.0 : 1024.0;
  final suffixes = unit == _BandwidthUnit.bits
      ? const ['b/s', 'Kb/s', 'Mb/s', 'Gb/s', 'Tb/s']
      : const ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];

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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.onPrimaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
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
