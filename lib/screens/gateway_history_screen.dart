import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  List<GatewayStatus> _gateways = const [];
  Object? _error;
  bool _loading = false;
  bool _appActive = true;
  Timer? _timer;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_appActive &&
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
    if (_appActive && mounted) _refresh();
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
