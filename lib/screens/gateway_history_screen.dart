import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../providers/session_provider.dart';
import '../widgets/gateway_history_panel.dart';

class GatewayHistoryScreen extends StatefulWidget {
  const GatewayHistoryScreen({super.key});

  @override
  State<GatewayHistoryScreen> createState() => _GatewayHistoryScreenState();
}

class _GatewayHistoryScreenState extends State<GatewayHistoryScreen>
    with WidgetsBindingObserver {
  static const _prefLive = 'gatewayHistory.live';
  static const _prefRefreshSeconds = 'gatewayHistory.refreshSeconds';

  List<GatewayStatus> _gateways = const [];
  Object? _error;
  bool _loading = false;
  bool _appActive = true;
  bool _preferencesLoaded = false;
  bool _live = true;
  int _refreshSeconds = 5;
  Timer? _timer;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedInterval = preferences.getInt(_prefRefreshSeconds) ?? 5;
    setState(() {
      _live = preferences.getBool(_prefLive) ?? true;
      _refreshSeconds = const {1, 3, 5, 10}.contains(savedInterval)
          ? savedInterval
          : 5;
      _preferencesLoaded = true;
    });
    _startTimer();
  }

  Future<void> _savePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_prefLive, _live);
    await preferences.setInt(_prefRefreshSeconds, _refreshSeconds);
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_preferencesLoaded) return;
    _timer = Timer.periodic(Duration(seconds: _refreshSeconds), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_live &&
          _appActive &&
          !_loading &&
          session.connected &&
          session.service != null) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _live && mounted) _refresh();
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
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      _gateways = const [];
      _error = null;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh(showSpinner: true);
        });
      }
    } else if (_gateways.isEmpty && session.connected && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(showSpinner: true);
      });
    }
  }

  Future<void> _refresh({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _gateways = const [];
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
      final data = await session.service!.getDashboard();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _gateways = data.gateways;
        _error = null;
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final identity = '${session.sessionGeneration}:${session.selectedProfile?.id ?? ''}';

    return RefreshIndicator(
      onRefresh: () => _refresh(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(
            children: [
              const Icon(Icons.public_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gateway monitoring',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : () => _refresh(showSpinner: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Live latency and packet-loss history for every reported gateway.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                selected: _live,
                avatar: Icon(_live ? Icons.sync : Icons.sync_disabled),
                label: Text(_live ? 'Live ${_refreshSeconds}s' : 'Paused'),
                onSelected: (value) {
                  setState(() => _live = value);
                  _savePreferences();
                  if (value) _refresh();
                },
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1s')),
                  ButtonSegment(value: 3, label: Text('3s')),
                  ButtonSegment(value: 5, label: Text('5s')),
                  ButtonSegment(value: 10, label: Text('10s')),
                ],
                selected: {_refreshSeconds},
                onSelectionChanged: (values) {
                  setState(() => _refreshSeconds = values.first);
                  _startTimer();
                  _savePreferences();
                  if (_live) _refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const _GatewayMessage(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            _GatewayMessage(
              icon: Icons.error_outline,
              text: _error.toString(),
            )
          else if (!_loading && _gateways.isEmpty)
            const _GatewayMessage(
              icon: Icons.public_off_outlined,
              text: 'No gateway telemetry returned by pfSense.',
            )
          else
            GatewayHistorySection(
              key: ValueKey(identity),
              gateways: _gateways,
            ),
        ],
      ),
    );
  }
}

class _GatewayMessage extends StatelessWidget {
  const _GatewayMessage({required this.icon, required this.text});

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
