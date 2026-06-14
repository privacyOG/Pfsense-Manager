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
  String? _busyService;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;

    if (changed) {
      _requestGeneration++;
      _services = [];
      _error = null;
      _busyService = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_services.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _services = [];
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
      final services = await session.service!.getServices();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _services = services;
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

  Future<void> _act(SystemService service, String action) async {
    if (_busyService != null) return;
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings?.confirm ?? 'Confirm'),
        content: Text(
          '${action.toUpperCase()} ${service.displayName}?\n\n'
          'This changes a live service on the selected pfSense firewall.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings?.confirm ?? 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;

    setState(() => _busyService = service.name);
    try {
      switch (action) {
        case 'start':
          await session.service!.startService(service.name);
        case 'stop':
          await session.service!.stopService(service.name);
        case 'restart':
          await session.service!.restartService(service.name);
      }

      if (!mounted ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }

      await _load(showSpinner: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${service.displayName} $action request completed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyService = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Services',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _loading || !session.connected
                    ? null
                    : () => _load(showSpinner: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            _message(
              Icons.cloud_off_outlined,
              strings?.disconnectedMessage ?? 'Disconnected',
            )
          else if (_error != null)
            _message(Icons.error_outline, _error.toString())
          else if (!_loading && _services.isEmpty)
            _message(
              Icons.miscellaneous_services_outlined,
              strings?.emptyState ?? 'Nothing to show yet.',
            ),
          if (session.connected)
            for (final service in _services)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        service.running
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        color: service.running ? Colors.green : Colors.grey,
                      ),
                      title: Text(service.displayName),
                      subtitle: Text(
                        service.running
                            ? (strings?.running ?? 'Running')
                            : (strings?.stopped ?? 'Stopped'),
                      ),
                      trailing: _busyService == service.name
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _busyService == null && !service.running
                              ? () => _act(service, 'start')
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(strings?.start ?? 'Start'),
                        ),
                        TextButton.icon(
                          onPressed: _busyService == null && service.running
                              ? () => _act(service, 'stop')
                              : null,
                          icon: const Icon(Icons.stop),
                          label: Text(strings?.stop ?? 'Stop'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busyService == null
                              ? () => _act(service, 'restart')
                              : null,
                          icon: const Icon(Icons.restart_alt),
                          label: Text(strings?.restart ?? 'Restart'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
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
