import 'dart:async';
import 'dart:math' as math;

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
  static const _prefLive = 'networkMonitor.live';
  static const _prefRefreshSeconds = 'networkMonitor.refreshSeconds';
  static const _prefQuickFilter = 'networkMonitor.quickFilter';

  final _search = TextEditingController();
  final Map<String, _InterfaceCounters> _previousCounters = {};
  final Map<String, _InterfaceRates> _rates = {};

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
      _states = [];
      _interfaces = [];
      _previousCounters.clear();
      _rates.clear();
      _lastSampleAt = null;
      _lastSuccessfulRefresh = null;
      _error = null;
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
        _states = [];
        _interfaces = [];
        _previousCounters.clear();
        _rates.clear();
        _lastSampleAt = null;
        _lastSuccessfulRefresh = null;
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
    }

    _previousCounters
      ..clear()
      ..addAll(nextCounters);
    _rates
      ..clear()
      ..addAll(nextRates);
    _lastSampleAt = now;
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

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _summaryCard(bytes: bytes, packets: packets),
          const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Text(
              'Interface traffic',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final interface in _interfaces)
              _interfaceCard(interface, _rates[_interfaceLabel(interface)]),
          ],
          const SizedBox(height: 12),
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

  Widget _summaryCard({required int bytes, required int packets}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                Switch(
                  value: _live,
                  onChanged: (value) {
                    setState(() => _live = value);
                    _savePreferences();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(label: Text('${_states.length} states')),
                Chip(label: Text(_formatBytes(bytes))),
                Chip(label: Text('$packets packets')),
              ],
            ),
            const SizedBox(height: 12),
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
                  _lastSampleAt = null;
                });
                _startTimer();
                _savePreferences();
                if (_live) _load();
              },
            ),
          ],
        ),
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

  Widget _interfaceCard(InterfaceStatus interface, _InterfaceRates? rates) {
    final label = _interfaceLabel(interface);
    final inRate = rates?.inBps ?? 0;
    final outRate = rates?.outBps ?? 0;
    return Card(
      child: ListTile(
        leading: Icon(
          interface.up ? Icons.link : Icons.link_off,
          color: interface.up ? Colors.green : Colors.grey,
        ),
        title: Text(label),
        subtitle: Text(
          'In ${_formatRate(inRate)}  •  Out ${_formatRate(outRate)}',
        ),
      ),
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
