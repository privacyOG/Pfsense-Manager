import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/system_info.dart';
import '../providers/session_provider.dart';
import '../widgets/system_info_details.dart';

class SystemInfoScreen extends StatefulWidget {
  const SystemInfoScreen({super.key});

  @override
  State<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends State<SystemInfoScreen> {
  SystemInfo? _info;
  Object? _error;
  bool _loading = false;
  bool _rebooting = false;
  int _requestGeneration = 0;
  int? _sessionGeneration;
  String? _profileId;
  String _appVersion = 'Unknown';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    }).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final changed = _sessionGeneration != session.sessionGeneration ||
        _profileId != session.selectedProfile?.id;
    if (changed) {
      _requestGeneration++;
      _sessionGeneration = session.sessionGeneration;
      _profileId = session.selectedProfile?.id;
      _info = null;
      _error = null;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
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
        _info = null;
        _error = AppLocalizations.of(context)?.disconnectedMessage ??
            'Disconnected';
      });
      return;
    }

    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });

    try {
      final info = await session.service!.getSystemInfo();
      if (!mounted ||
          request != _requestGeneration ||
          generation != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _info = info;
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

  Future<bool?> _confirm(String message) {
    final strings = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings?.confirm ?? 'Confirm'),
        content: Text(message),
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
  }

  Future<void> _reboot() async {
    final strings = AppLocalizations.of(context);
    if (await _confirm(strings?.rebootConfirm ??
            'Reboot this pfSense system?') !=
        true) {
      return;
    }
    if (await _confirm(strings?.rebootFinalConfirm ?? 'Confirm reboot') !=
        true) {
      return;
    }

    setState(() => _rebooting = true);
    try {
      await context.read<PfSenseSessionProvider>().service!.rebootSystem();
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
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final info = _info;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings?.systemInfo ?? 'System information',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh system information',
                onPressed: _loading ? null : () => _load(showSpinner: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pull down to update firmware, repository and system status.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            _message(Icons.cloud_off_outlined,
                strings?.disconnectedMessage ?? 'Disconnected')
          else if (_error != null)
            _message(Icons.error_outline, _error.toString())
          else if (info == null && !_loading)
            _message(Icons.info_outline,
                strings?.emptyState ?? 'Nothing to show yet.')
          else if (info != null)
            SystemInfoDetails(
              info: info,
              appVersion: _appVersion,
              rebooting: _rebooting,
              onReboot: _reboot,
            ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(text)),
    );
  }
}
