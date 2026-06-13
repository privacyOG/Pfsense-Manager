import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/system_service.dart';
import '../providers/session_provider.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<SystemService> _services = [];
  bool _loading = false;
  Object? _error;
  String? _busy;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services.isEmpty && !_loading) _load(showSpinner: true);
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
      final list = await s.service!.getServices();
      if (mounted) {
        setState(() {
          _services = list;
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

  Future<void> _act(SystemService svc, String action) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(l?.confirm ?? 'Confirm'),
                content: Text('${action.toUpperCase()} ${svc.displayName}?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(l?.cancel ?? 'Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(l?.confirm ?? 'Confirm'))
                ]));
    if (ok != true) return;
    if (!mounted) return;
    final s = context.read<PfSenseSessionProvider>();
    setState(() => _busy = svc.name);
    try {
      if (action == 'start') await s.service!.startService(svc.name);
      if (action == 'stop') await s.service!.stopService(svc.name);
      if (action == 'restart') await s.service!.restartService(svc.name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.watch<PfSenseSessionProvider>();
    return RefreshIndicator(
        onRefresh: () => _load(showSpinner: true),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!s.connected)
            _msg(Icons.cloud_off_outlined,
                l?.disconnectedMessage ?? 'Disconnected')
          else if (_loading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _msg(Icons.error_outline, _error.toString())
          else if (_services.isEmpty)
            _msg(Icons.miscellaneous_services_outlined,
                l?.emptyState ?? 'Nothing to show yet.')
          else
            for (final svc in _services)
              Card(
                  child: Column(children: [
                ListTile(
                    leading: Icon(
                        svc.running
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        color: svc.running ? Colors.green : Colors.grey),
                    title: Text(svc.displayName),
                    subtitle: Text(svc.running
                        ? (l?.running ?? 'Running')
                        : (l?.stopped ?? 'Stopped')),
                    trailing: _busy == svc.name
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : null),
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                      onPressed: _busy == null && !svc.running
                          ? () => _act(svc, 'start')
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l?.start ?? 'Start')),
                  TextButton.icon(
                      onPressed: _busy == null && svc.running
                          ? () => _act(svc, 'stop')
                          : null,
                      icon: const Icon(Icons.stop),
                      label: Text(l?.stop ?? 'Stop')),
                  FilledButton.tonalIcon(
                      onPressed:
                          _busy == null ? () => _act(svc, 'restart') : null,
                      icon: const Icon(Icons.restart_alt),
                      label: Text(l?.restart ?? 'Restart'))
                ])
              ]))
        ]));
  }

  Widget _msg(IconData i, String t) =>
      Card(child: ListTile(leading: Icon(i), title: Text(t)));
}
