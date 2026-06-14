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
        _error = AppLocalizations.of(context)?.disconnectedMessage ?? 'Disconnected';
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
      final logs = await session.service!.getFirewallLogs(
        action: _action == 'all' ? null : _action,
      );
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
    final query = _search.text.trim().toLowerCase();
    final visible = _logs.where((log) {
      if (query.isEmpty) return true;
      return [
        log.sourceIp,
        log.destinationIp,
        log.interface,
        log.protocol,
        log.reason,
        log.portInfo,
        log.action,
      ].join(' ').toLowerCase().contains(query);
    }).toList();

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
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: InputDecoration(labelText: strings?.action ?? 'Action'),
            items: [
              DropdownMenuItem(value: 'all', child: Text(strings?.all ?? 'All')),
              DropdownMenuItem(value: 'PASS', child: Text(strings?.pass ?? 'Pass')),
              DropdownMenuItem(value: 'BLOCK', child: Text(strings?.block ?? 'Block')),
              DropdownMenuItem(value: 'REJECT', child: Text(strings?.reject ?? 'Reject')),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _action = value);
                    _load(showSpinner: true);
                  },
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
    final color = switch (log.action.toUpperCase()) {
      'PASS' => Colors.green,
      'BLOCK' || 'BLOCK6' => Colors.red,
      'REJECT' || 'REJECT6' => Colors.orange,
      _ => Colors.grey,
    };
    final initial = log.action.isEmpty ? '?' : log.action.substring(0, 1);
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
          label: Text(log.action),
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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}
