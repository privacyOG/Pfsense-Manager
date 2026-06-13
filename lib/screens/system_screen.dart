import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/system_info.dart';
import '../providers/session_provider.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  SystemInfo? _info;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = context.read<PfSenseSessionProvider>().service;
    if (service == null) {
      setState(() => _error = AppStrings.of(context).t('offline'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await service.getSystemInfo();
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reboot() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(strings.t('reboot')),
        content: const Text('This will reboot the selected pfSense firewall.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.t('confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<PfSenseSessionProvider>().service?.rebootSystem();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final info = _info;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          if (info != null) ...[
            _row('Version', info.version),
            _row('Platform', info.platform),
            _row('Architecture', info.architecture),
            _row('Build time', info.buildTime),
            _row('PHP', info.phpVersion),
            _row('Kernel', info.kernelVersion),
            _row('Repository', info.repositoryType),
            if (info.lastUpdate != null) _row('Last update', info.lastUpdate!),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _reboot,
            icon: const Icon(Icons.power_settings_new),
            label: Text(strings.t('reboot')),
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
}
