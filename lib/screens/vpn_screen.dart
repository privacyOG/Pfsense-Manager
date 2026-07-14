import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/openvpn_status.dart';
import '../models/system_service.dart';
import '../models/wireguard_tunnel.dart';
import '../providers/session_provider.dart';
import '../widgets/slide_to_confirm.dart';
import 'vpn_management_screen.dart';

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  List<OpenVpnServerStatus> _openVpn = [];
  List<SystemService> _openVpnServices = [];
  SystemService? _tailscale;
  List<WireGuardTunnel> _wireGuard = [];
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
      _openVpnServices = [];
      _tailscale = null;
      _wireGuard = [];
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
        _openVpnServices = [];
        _tailscale = null;
        _wireGuard = [];
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
        session.service!.getWireGuardStatus(),
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
        _openVpn = (results[0] as List<Map<String, dynamic>>)
            .map(OpenVpnServerStatus.fromJson)
            .toList();
        _openVpnServices =
            services.where((service) => service.isOpenVpn).toList();
        _tailscale = tailscale;
        _wireGuard = results[2] as List<WireGuardTunnel>;
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

  Future<void> _openManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const VpnManagementScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _restart({
    required String actionKey,
    required String title,
    required Future<void> Function() action,
  }) async {
    if (_busyAction != null) return;
    final strings = AppStrings.of(context);
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: strings.f('restartService', {'service': title}),
      body: strings.f('restartServiceBody', {'service': title}),
      slideLabel: strings.t('slideToRestart'),
      icon: Icons.refresh,
    );
    if (confirmed != true || !mounted) return;
    await _runServiceAction(
      actionKey: actionKey,
      title: title,
      actionLabel: 'restart',
      action: action,
    );
  }

  Future<void> _controlOpenVpnService(
    SystemService service,
    String action,
  ) async {
    if (_busyAction != null) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    final bool confirmed;
    if (action == 'stop') {
      confirmed =
          await showSlideToConfirmSheet(
            context: context,
            title: 'Stop ${service.instanceLabel}?',
            body:
                'Stopping this exact OpenVPN instance disconnects its active clients and leaves the configuration unchanged.',
            slideLabel: 'Slide to stop instance',
            icon: Icons.stop_circle_outlined,
          ) ==
          true;
    } else {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('Start ${service.instanceLabel}?'),
              content: const Text(
                'Start this exact OpenVPN service instance using its current configuration?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Start'),
                ),
              ],
            ),
          ) ==
          true;
    }
    if (!confirmed || !mounted) return;

    await _runServiceAction(
      actionKey: service.instanceKey,
      title: service.instanceLabel,
      actionLabel: action,
      action: () => action == 'start'
          ? session.service!.startServiceInstance(service)
          : session.service!.stopServiceInstance(service),
    );
  }

  Future<void> _runServiceAction({
    required String actionKey,
    required String title,
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    setState(() => _busyAction = actionKey);
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title $actionLabel request completed.')),
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

  Widget _openVpnServerCard(
    OpenVpnServerStatus server,
    PfSenseSessionProvider session,
  ) {
    final service = matchOpenVpnService(server, _openVpnServices);
    final unavailable = service == null || !session.connected || _loading;
    return _OpenVpnServerCard(
      server: server,
      service: service,
      busy: service != null && _busyAction == service.instanceKey,
      onStart: unavailable || service.running
          ? null
          : () => _controlOpenVpnService(service, 'start'),
      onStop: unavailable || !service.running
          ? null
          : () => _controlOpenVpnService(service, 'stop'),
      onRestart: unavailable
          ? null
          : () => _restart(
                actionKey: service.instanceKey,
                title: service.instanceLabel,
                action: () => session.service!.restartServiceInstance(service),
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final canManageVpn =
        session.vpnManagementService?.capabilities.canReadAnything == true;
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
                strings.f(
                  'lastUpdated',
                  {'time': _formatTime(_lastSuccessfulRefresh!)},
                ),
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
              leading: const Icon(Icons.settings_input_component_outlined),
              title: const Text('VPN configuration'),
              subtitle: const Text(
                'Manage capability-reported OpenVPN, IPsec and WireGuard configuration separately from live status.',
              ),
              trailing: IconButton(
                key: const Key('open-vpn-management'),
                tooltip: 'Configure VPN',
                onPressed: canManageVpn && _busyAction == null
                    ? _openManagement
                    : null,
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ),

          // ── OpenVPN ──────────────────────────────────────────────────────
          Card(
            child: ListTile(
              leading: const Icon(Icons.vpn_lock),
              title: Text(strings.t('openvpn')),
              subtitle: Text(
                '${_openVpn.length} service instances · '
                '${strings.f('vpnConnectionsCount', {
                  'count': openVpnConnectionCount(_openVpn).toString(),
                })}',
              ),
            ),
          ),
          for (final server in _openVpn) _openVpnServerCard(server, session),

          // ── WireGuard ─────────────────────────────────────────────────────
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outlined),
              title: const Text('WireGuard'),
              subtitle: Text(
                _wireGuard.isEmpty
                    ? strings.t('noWireGuardTunnels')
                    : strings.f(
                        'wireGuardTunnelCount',
                        {'count': _wireGuard.length.toString()},
                      ),
              ),
              trailing: _busyAction == 'wireguard'
                  ? const CircularProgressIndicator()
                  : IconButton(
                      tooltip: strings.t('restartWireGuard'),
                      onPressed: session.connected &&
                              !_loading &&
                              _wireGuard.isNotEmpty
                          ? () => _restart(
                                actionKey: 'wireguard',
                                title: 'WireGuard',
                                action: () => session.service!.restartWireGuard(),
                              )
                          : null,
                      icon: const Icon(Icons.restart_alt),
                    ),
            ),
          ),
          for (final tunnel in _wireGuard) ...[
            _WireGuardTunnelCard(tunnel: tunnel),
          ],

          // ── Tailscale ─────────────────────────────────────────────────────
          if (_tailscale != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub),
                title: Text(strings.t('tailscale')),
                subtitle: Text(
                  [
                    _tailscale!.running
                        ? strings.t('running')
                        : strings.t('stopped'),
                    if (_tailscale!.instanceDetails.isNotEmpty)
                      _tailscale!.instanceDetails,
                  ].join(' · '),
                ),
                trailing: _busyAction == _tailscale!.instanceKey
                    ? const CircularProgressIndicator()
                    : IconButton(
                        tooltip: strings.t('restart'),
                        onPressed: session.connected && !_loading
                            ? () => _restart(
                                  actionKey: _tailscale!.instanceKey,
                                  title: _tailscale!.instanceLabel,
                                  action: () => session.service!
                                      .restartServiceInstance(_tailscale!),
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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

class _OpenVpnServerCard extends StatelessWidget {
  const _OpenVpnServerCard({
    required this.server,
    required this.service,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final OpenVpnServerStatus server;
  final SystemService? service;
  final bool busy;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final details = [
      if (server.mode.isNotEmpty) server.mode,
      if (server.port.isNotEmpty) 'Port ${server.port}',
      if (server.vpnId.isNotEmpty) 'VPN ID ${server.vpnId}',
      if (service?.id != null) 'Service #${service!.id}',
      strings.f('vpnConnectionsCount', {
        'count': server.connections.length.toString(),
      }),
    ].join(' · ');

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.vpn_key_outlined),
        title: Text(server.displayName),
        subtitle: Text(details),
        trailing: busy
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: service == null
                    ? 'No matching OpenVPN service instance'
                    : 'Restart ${service!.instanceLabel}',
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
              ),
        children: [
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              TextButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              FilledButton.tonalIcon(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart'),
              ),
            ],
          ),
          if (server.connections.isEmpty)
            ListTile(
              dense: true,
              title: Text(strings.t('noAdditionalStatus')),
            )
          else
            for (final connection in server.connections)
              ListTile(
                dense: true,
                leading: const Icon(Icons.devices_other, size: 18),
                title: Text(connection.displayName),
                subtitle: Text(
                  [
                    if (connection.remoteHost.isNotEmpty) connection.remoteHost,
                    if (connection.status.isNotEmpty) connection.status,
                  ].join(' · '),
                ),
              ),
        ],
      ),
    );
  }
}

class _WireGuardTunnelCard extends StatelessWidget {
  const _WireGuardTunnelCard({required this.tunnel});
  final WireGuardTunnel tunnel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabledColor = tunnel.enabled ? const Color(0xFF00C2A8) : scheme.error;

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: enabledColor.withValues(alpha: 0.12),
          child: Icon(Icons.lock_outlined, color: enabledColor, size: 20),
        ),
        title: Text(
          tunnel.description.isNotEmpty ? tunnel.description : tunnel.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Builder(builder: (context) {
          final s = AppStrings.of(context);
          return Text(
            [
              tunnel.enabled ? s.t('active') : s.t('disabled'),
              if (tunnel.listenPort.isNotEmpty) 'Port ${tunnel.listenPort}',
              s.f('peerCount', {'count': tunnel.peers.length.toString()}),
            ].join(' · '),
          );
        }),
        children: [
          if (tunnel.publicKey.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.vpn_key_outlined, size: 18),
              title: Text(AppStrings.of(context).t('publicKey')),
              subtitle: Text(
                tunnel.publicKey,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final peer in tunnel.peers) _PeerTile(peer: peer),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});
  final WireGuardPeer peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final handshake = peer.lastHandshake;
    final handshakeAge =
        handshake != null ? DateTime.now().difference(handshake) : null;
    final recentHandshake =
        handshakeAge != null && handshakeAge.inMinutes < 3;
    final handshakeColor = handshake == null
        ? scheme.onSurfaceVariant
        : recentHandshake
            ? const Color(0xFF00C2A8)
            : scheme.error;

    final strings = AppStrings.of(context);
    String? handshakeLabel;
    if (handshake != null) {
      if (handshakeAge!.inSeconds < 60) {
        handshakeLabel = strings.f(
          'handshakeSecondsAgo',
          {'n': handshakeAge.inSeconds.toString()},
        );
      } else if (handshakeAge.inMinutes < 60) {
        handshakeLabel = strings.f(
          'handshakeMinutesAgo',
          {'n': handshakeAge.inMinutes.toString()},
        );
      } else if (handshakeAge.inHours < 24) {
        handshakeLabel = strings.f(
          'handshakeHoursAgo',
          {'n': handshakeAge.inHours.toString()},
        );
      } else {
        handshakeLabel = strings.f(
          'handshakeDaysAgo',
          {'n': handshakeAge.inDays.toString()},
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    peer.description.isNotEmpty
                        ? peer.description
                        : strings.t('peerLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (handshakeLabel != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.handshake_outlined,
                        size: 14,
                        color: handshakeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        handshakeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: handshakeColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (peer.endpoint != null) ...[
              const SizedBox(height: 4),
              Text(
                '${strings.t('endpoint')}: ${peer.endpoint}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (peer.allowedIps.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${strings.t('allowedIps')}: ${peer.allowedIps.join(', ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
