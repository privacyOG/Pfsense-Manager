import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../models/network_state.dart';
import '../providers/session_provider.dart';

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
    setState(() {
      _live = preferences.getBool(_prefLive) ?? true;
      _refreshSeconds = allowedIntervals.contains(savedInterval)
          ? savedInterval
          : math.max(_minimumRefreshSeconds, savedInterval);
      _quickFilter = preferences.getString(_prefQuickFilter) ?? 'all';
      _preferencesLoaded = true;
    });
    _startTimer();
  }

  Future<void> _savePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_prefLive, _live);
    await preferences.setInt(_prefRefreshSeconds, _refreshSeconds);
    await preferences.setString(_prefQuickFilter, _quickFilter);
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
      history.add(_RateSample(capturedAt: now, inBps: inRate, outBps: outRate));
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
    final bytes = _states.fold<int>(0, (sum, state) => sum + state.bytes);
    final packets = _states.fold<int>(0, (sum, state) => sum + state.packets);
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
          _summaryCard(bytes: bytes, packets: packets, rates: totalRates),
          const SizedBox(height: 14),
          _TrafficChartCard(
            title: 'Live throughput',
            subtitle: 'Combined traffic across all reported interfaces',
            history: _totalHistory,
            height: 220,
          ),
          const SizedBox(height: 10),
          if (_lastSuccessfulRefresh != null)
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

  Widget _summaryCard({
    required int bytes,
    required int packets,
    required _InterfaceRates rates,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17385D), Color(0xFF0A1F36)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
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
              const Icon(Icons.monitor_heart_outlined,
                  color: Color(0xFF8BC1FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Real-time Network Activity',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Inbound',
                  value: _formatRate(rates.inBps),
                  icon: Icons.south_west,
                  color: const Color(0xFF63E6BE),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Outbound',
                  value: _formatRate(rates.outBps),
                  icon: Icons.north_east,
                  color: const Color(0xFFFFB86B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DarkChip(label: '${_states.length} states'),
              _DarkChip(label: _formatBytes(bytes)),
              _DarkChip(label: '$packets packets'),
            ],
          ),
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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Color _interfaceAccent(int index) {
    const accents = [
      Color(0xFF63E6BE),
      Color(0xFF74C0FC),
      Color(0xFFFFB86B),
      Color(0xFFB197FC),
      Color(0xFF4DABF7),
      Color(0xFFFF8787),
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
  });

  final InterfaceStatus interface;
  final _InterfaceRates? rates;
  final List<_RateSample> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = _interfaceLabel(interface);
    final inRate = rates?.inBps ?? 0;
    final outRate = rates?.outBps ?? 0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF102741),
        border: Border.all(color: accent.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
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
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
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
                      'IN  ${_formatRate(inRate)}',
                      style: const TextStyle(
                        color: Color(0xFF63E6BE),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'OUT  ${_formatRate(outRate)}',
                      style: const TextStyle(
                        color: Color(0xFFFFB86B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 94,
              child: _MiniTrafficChart(history: history, accent: accent),
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
  });

  final String title;
  final String subtitle;
  final List<_RateSample> history;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0B1C30),
        border: Border.all(color: const Color(0xFF2B4E72)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF9CB3CA)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: height,
            child: _FullTrafficChart(history: history),
          ),
        ],
      ),
    );
  }
}

class _FullTrafficChart extends StatelessWidget {
  const _FullTrafficChart({required this.history});

  final List<_RateSample> history;

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const _ChartPlaceholder();
    }

    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      inSpots.add(FlSpot(i.toDouble(), history[i].inBps));
      outSpots.add(FlSpot(i.toDouble(), history[i].outBps));
    }
    final maxY = math.max(
      1024.0,
      history.fold<double>(
        0,
        (current, sample) =>
            math.max(current, math.max(sample.inBps, sample.outBps)),
      ) * 1.2,
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, history.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(1, maxY / 4),
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                _formatRate(value),
                style: const TextStyle(
                  color: Color(0xFF8FA7BE),
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${spot.barIndex == 0 ? 'In' : 'Out'} ${_formatRate(spot.y)}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          _lineData(inSpots, const Color(0xFF63E6BE), fill: true),
          _lineData(outSpots, const Color(0xFFFFB86B), fill: false),
        ],
      ),
    );
  }
}

class _MiniTrafficChart extends StatelessWidget {
  const _MiniTrafficChart({required this.history, required this.accent});

  final List<_RateSample> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const _ChartPlaceholder(compact: true);
    }
    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      inSpots.add(FlSpot(i.toDouble(), history[i].inBps));
      outSpots.add(FlSpot(i.toDouble(), history[i].outBps));
    }
    final maxY = math.max(
      1024.0,
      history.fold<double>(
        0,
        (current, sample) =>
            math.max(current, math.max(sample.inBps, sample.outBps)),
      ) * 1.15,
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, history.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _lineData(inSpots, accent, fill: true),
          _lineData(outSpots, const Color(0xFFFFB86B), fill: false),
        ],
      ),
    );
  }
}

LineChartBarData _lineData(
  List<FlSpot> spots,
  Color color, {
  required bool fill,
}) {
  return LineChartBarData(
    spots: spots,
    isCurved: true,
    curveSmoothness: 0.22,
    color: color,
    barWidth: 2.2,
    isStrokeCapRound: true,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(
      show: fill,
      color: color.withOpacity(0.13),
    ),
  );
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
        style: const TextStyle(color: Color(0xFF8199B2)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
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
                  style: const TextStyle(
                    color: Color(0xFFAFC0D1),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
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

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD4E1EC),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _interfaceLabel(InterfaceStatus interface) {
  final description = interface.description.trim();
  if (description.isNotEmpty) return description;
  final name = interface.name.trim();
  if (name.isNotEmpty) return name.toUpperCase();
  final hardware = interface.hardwareInterface.trim();
  return hardware.isEmpty ? 'unknown' : hardware;
}

String _formatRate(double bytesPerSecond) =>
    '${_formatBytes(bytesPerSecond.round())}/s';

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
