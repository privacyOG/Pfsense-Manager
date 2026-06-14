import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/system_service.dart';
import '../providers/session_provider.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  List<Map<String, dynamic>> _openVpn = [];
  SystemService? _tailscale;
  Object? _error;
  bool _loading = false;
  String? _busyAction;
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
      _openVpn = [];
      _tailscale = null;
      _error = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _openVpn = [];
        _tailscale = null;
        _lastSuccessfulRefresh = null;
        _error = AppStrings.of(context).t('offline');
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        session.service!.getOpenVPNStatus(),
        session.service!.getServices(),
      ]);
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      final services = results[1] as List<SystemService>;
      SystemService? tailscale;
      for (final service in services) {
        final name = service.name.toLowerCase();
        final display = service.displayName.toLowerCase();
        if (name.contains('tailscale') || display.contains('tailscale')) {
          tailscale = service;
          break;
        }
      }
      setState(() {
        _openVpn = results[0] as List<Map<String, dynamic>>;
        _tailscale = tailscale;
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

  Future<void> _restart(String title, Future<void> Function() action) async {
    if (_busyAction != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restart $title?'),
        content: Text('Active $title connections may be interrupted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyAction = title);
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title restart request completed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_lastSuccessfulRefresh != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!session.connected)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(strings.t('offline')),
              ),
            )
          else if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error.toString()),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.vpn_lock),
              title: Text(strings.t('openvpn')),
              subtitle: Text('${_openVpn.length} connection(s) reported'),
              trailing: _busyAction == 'OpenVPN'
                  ? const CircularProgressIndicator()
                  : IconButton(
                      tooltip: strings.t('restart'),
                      onPressed: session.connected && !_loading
                          ? () => _restart(
                                'OpenVPN',
                                () => session.service!.restartOpenVPN(),
                              )
                          : null,
                      icon: const Icon(Icons.restart_alt),
                    ),
            ),
          ),
          for (final item in _openVpn)
            Card(
              child: ListTile(
                title: Text(_firstText(item, const ['common_name', 'name'], 'OpenVPN')),
                subtitle: Text(
                  _firstText(item, const ['remote_host', 'status'], 'No additional status'),
                ),
              ),
            ),
          if (_tailscale != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub),
                title: Text(strings.t('tailscale')),
                subtitle: Text(_tailscale!.running ? 'Running' : 'Stopped'),
                trailing: _busyAction == 'Tailscale'
                    ? const CircularProgressIndicator()
                    : IconButton(
                        tooltip: strings.t('restart'),
                        onPressed: session.connected && !_loading
                            ? () => _restart(
                                  'Tailscale',
                                  () => session.service!.restartService(_tailscale!.name),
                                )
                            : null,
                        icon: const Icon(Icons.restart_alt),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _firstText(Map<String, dynamic> item, List<String> keys, String fallback) {
    for (final key in keys) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
