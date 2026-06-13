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

class _FirewallLogsScreenState extends State<FirewallLogsScreen> {
  final _search = TextEditingController();
  List<FirewallLog> _logs = [];
  String _action = 'all';
  bool _auto = true;
  bool _loading = false;
  Object? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_auto) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logs.isEmpty && !_loading) _load(showSpinner: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    final s = context.read<PfSenseSessionProvider>();
    if (!s.connected || s.service == null) {
      setState(
          () => _error = AppLocalizations.of(context)?.disconnectedMessage);
      return;
    }
    if (showSpinner) setState(() => _loading = true);
    try {
      final logs = await s.service!
          .getFirewallLogs(action: _action == 'all' ? null : _action);
      if (mounted) {
        setState(() {
          _logs = logs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted && showSpinner) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.watch<PfSenseSessionProvider>();
    final q = _search.text.trim().toLowerCase();
    final v = _logs
        .where((x) =>
            q.isEmpty ||
            x.sourceIp.toLowerCase().contains(q) ||
            x.destinationIp.toLowerCase().contains(q))
        .toList();
    return RefreshIndicator(
        onRefresh: () => _load(showSpinner: true),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
              controller: _search,
              decoration: InputDecoration(
                  labelText: l?.searchIp ?? 'Search IP',
                  prefixIcon: const Icon(Icons.search))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
              initialValue: _action,
              decoration: InputDecoration(labelText: l?.action ?? 'Action'),
              items: [
                DropdownMenuItem(value: 'all', child: Text(l?.all ?? 'All')),
                DropdownMenuItem(value: 'PASS', child: Text(l?.pass ?? 'Pass')),
                DropdownMenuItem(
                    value: 'BLOCK', child: Text(l?.block ?? 'Block')),
                DropdownMenuItem(
                    value: 'REJECT', child: Text(l?.reject ?? 'Reject'))
              ],
              onChanged: (x) {
                if (x != null) {
                  setState(() => _action = x);
                  _load(showSpinner: true);
                }
              }),
          SwitchListTile(
              value: _auto,
              onChanged: (x) => setState(() => _auto = x),
              title: Text(l?.autoRefresh ?? 'Auto refresh'),
              secondary: const Icon(Icons.autorenew)),
          if (!s.connected)
            _msg(Icons.cloud_off_outlined,
                l?.disconnectedMessage ?? 'Disconnected')
          else if (_loading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _msg(Icons.error_outline, _error.toString())
          else if (v.isEmpty)
            _msg(
                Icons.article_outlined, l?.emptyState ?? 'Nothing to show yet.')
          else
            for (final log in v) _tile(log)
        ]));
  }

  Widget _tile(FirewallLog log) {
    final c = switch (log.action.toUpperCase()) {
      'PASS' => Colors.green,
      'BLOCK' || 'BLOCK6' => Colors.red,
      'REJECT' || 'REJECT6' => Colors.orange,
      _ => Colors.grey
    };
    return Card(
        child: ListTile(
            leading: CircleAvatar(
                backgroundColor: c.withValues(alpha: .16),
                child: Text(log.action.substring(0, 1),
                    style: TextStyle(color: c))),
            title: Text('${log.sourceIp} -> ${log.destinationIp}'),
            subtitle: Text(
                '${log.formattedTime} | ${log.interface} | ${log.protocol} ${log.portInfo}'),
            trailing: Chip(
                label: Text(log.action),
                backgroundColor: c.withValues(alpha: .14)),
            onTap: log.reason.isEmpty
                ? null
                : () => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(log.reason)))));
  }

  Widget _msg(IconData i, String t) =>
      Card(child: ListTile(leading: Icon(i), title: Text(t)));
}
