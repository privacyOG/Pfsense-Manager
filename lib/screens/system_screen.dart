import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/system_info.dart';
import '../providers/session_provider.dart';
import '../widgets/slide_to_confirm.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  SystemInfo? _info;
  Object? _error;
  bool _loading = false;
  bool _rebooting = false;
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
      _info = null;
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
        _info = null;
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
      final info = await session.service!.getSystemInfo();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _info = info;
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

  Future<void> _reboot() async {
    if (_rebooting) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    final profileName = session.selectedProfile?.name ?? 'selected firewall';
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Reboot firewall?',
      body:
          'This will reboot $profileName. Network access and all services may be unavailable for several minutes.',
      slideLabel: 'Slide to reboot',
      icon: Icons.restart_alt,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _rebooting = true);
    try {
      await session.service!.rebootSystem();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reboot request accepted. The firewall may disconnect while restarting.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _rebooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final info = _info;

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
          if (session.connected && info != null) ...[
            _row('Version', info.version),
            _row('Platform', info.platform),
            _row('Architecture', info.architecture),
            _row('Build time', info.buildTime),
            _row('PHP', info.phpVersion),
            _row('Kernel', info.kernelVersion),
            _row('Repository', info.repositoryType ?? 'Not reported'),
            if (info.lastUpdate != null) _row('Last update', info.lastUpdate!),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: session.connected && !_loading && !_rebooting
                ? _reboot
                : null,
            icon: _rebooting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.power_settings_new),
            label: Text(_rebooting ? 'Sending reboot request…' : strings.t('reboot')),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(value.isEmpty ? '-' : value),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
