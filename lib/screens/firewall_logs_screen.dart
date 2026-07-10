import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/firewall_log.dart';
import '../providers/session_provider.dart';

class FirewallLogsScreen extends StatefulWidget {
  const FirewallLogsScreen({super.key});

  @override
  State<FirewallLogsScreen> createState() => _FirewallLogsScreenState();
}

class _FirewallLogsScreenState extends State<FirewallLogsScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  List<FirewallLog> _logs = [];
  String _action = 'all';
  String _timeRange = 'all';
  bool _autoRefresh = true;
  bool _loading = false;
  bool _appActive = true;
  Object? _error;
  Timer? _timer;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_autoRefresh && _appActive && session.connected && !_loading) {
        _load();
      }
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
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
      _logs = [];
      _error = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_logs.isEmpty && !_loading && session.connected) {
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
        _logs = [];
        _lastSuccessfulRefresh = null;
        _error =
            AppLocalizations.of(context)?.disconnectedMessage ?? 'Disconnected';
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
      final logs = await session.service!.getFirewallLogs(limit: 250);
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _logs = logs;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final visible = filterFirewallLogs(
      _logs,
      action: _action == 'all' ? null : _action,
      query: _search.text,
      since: _timeCutoff(DateTime.now()),
    );

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: strings?.searchIp ?? 'Search logs',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('firewall-log-action-filter'),
                  initialValue: _action,
                  decoration:
                      InputDecoration(labelText: strings?.action ?? 'Action'),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(strings?.all ?? 'All'),
                    ),
                    DropdownMenuItem(
                      value: 'PASS',
                      child: Text(strings?.pass ?? 'Pass'),
                    ),
                    DropdownMenuItem(
                      value: 'BLOCK',
                      child: Text(strings?.block ?? 'Block'),
                    ),
                    DropdownMenuItem(
                      value: 'REJECT',
                      child: Text(strings?.reject ?? 'Reject'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _action = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('firewall-log-time-filter'),
                  initialValue: _timeRange,
                  decoration: const InputDecoration(labelText: 'Time range'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All available')),
                    DropdownMenuItem(value: '15m', child: Text('Last 15 minutes')),
                    DropdownMenuItem(value: '1h', child: Text('Last hour')),
                    DropdownMenuItem(value: '6h', child: Text('Last 6 hours')),
                    DropdownMenuItem(value: '24h', child: Text('Last 24 hours')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _timeRange = value);
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            value: _autoRefresh,
            onChanged: (value) => setState(() => _autoRefresh = value),
            title: Text(strings?.autoRefresh ?? 'Auto refresh'),
            secondary: const Icon(Icons.autorenew),
          ),
          if (_lastSuccessfulRefresh != null)
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            _message(
              Icons.cloud_off_outlined,
              strings?.disconnectedMessage ?? 'Disconnected',
            )
          else if (_error != null)
            _message(Icons.error_outline, _error.toString())
          else if (!_loading && visible.isEmpty)
            _message(
              Icons.article_outlined,
              strings?.emptyState ?? 'Nothing to show yet.',
            ),
          if (session.connected)
            for (final log in visible) _tile(log),
        ],
      ),
    );
  }

  Widget _tile(FirewallLog log) {
    if (!log.isParsed) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.code_off_outlined)),
          title: const Text('Unparsed firewall log'),
          subtitle: Text(
            log.rawText.isEmpty ? 'Empty log entry' : log.rawText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final action = canonicalFirewallAction(log.action);
    final color = switch (action) {
      'PASS' => Colors.green,
      'BLOCK' => Colors.red,
      'REJECT' => Colors.orange,
      _ => Colors.grey,
    };
    final initial = action.isEmpty ? '?' : action.substring(0, 1);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Text(initial, style: TextStyle(color: color)),
        ),
        title: Text('${log.sourceIp} → ${log.destinationIp}'),
        subtitle: Text(
          '${log.formattedTime} | ${log.interface} | ${log.protocol} ${log.portInfo}',
        ),
        trailing: Chip(
          label: Text(action),
          backgroundColor: color.withValues(alpha: .14),
        ),
        onTap: log.reason.isEmpty
            ? null
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(log.reason)),
                ),
      ),
    );
  }

  DateTime? _timeCutoff(DateTime now) => switch (_timeRange) {
        '15m' => now.subtract(const Duration(minutes: 15)),
        '1h' => now.subtract(const Duration(hours: 1)),
        '6h' => now.subtract(const Duration(hours: 6)),
        '24h' => now.subtract(const Duration(hours: 24)),
        _ => null,
      };

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}
