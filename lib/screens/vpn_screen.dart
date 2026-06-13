import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/session_provider.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  List<Map<String, dynamic>> _openVpn = [];
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
      final status = await service.getOpenVPNStatus();
      if (mounted) setState(() => _openVpn = status);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.vpn_lock),
              title: Text(strings.t('openvpn')),
              subtitle: Text('${_openVpn.length} connection(s) reported'),
              trailing: IconButton(
                tooltip: strings.t('restart'),
                onPressed: () async {
                  await context
                      .read<PfSenseSessionProvider>()
                      .service
                      ?.restartOpenVPN();
                  await _load();
                },
                icon: const Icon(Icons.restart_alt),
              ),
            ),
          ),
          for (final item in _openVpn)
            Card(
              child: ListTile(
                title: Text(
                  '${item['common_name'] ?? item['name'] ?? 'OpenVPN'}',
                ),
                subtitle: Text(
                  '${item['remote_host'] ?? item['status'] ?? item}',
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.hub),
              title: Text(strings.t('tailscale')),
              subtitle: const Text(
                'Managed via the pfSense Tailscale service package when present',
              ),
              trailing: IconButton(
                tooltip: strings.t('restart'),
                onPressed: () async {
                  await context
                      .read<PfSenseSessionProvider>()
                      .service
                      ?.restartService('tailscaled');
                },
                icon: const Icon(Icons.restart_alt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
