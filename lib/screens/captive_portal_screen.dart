import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/captive_portal_session.dart';
import '../models/captive_portal_voucher.dart';
import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../widgets/pfrest_feature_gate.dart';
import '../widgets/state_message.dart';

class CaptivePortalScreen extends StatefulWidget {
  const CaptivePortalScreen({super.key});

  @override
  State<CaptivePortalScreen> createState() => _CaptivePortalScreenState();
}

class _CaptivePortalScreenState extends State<CaptivePortalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final sessions = registry.decision(PfRestFeature.captivePortalSessions);
    final disconnect = registry.decision(PfRestFeature.captivePortalDisconnect);
    final vouchers = registry.decision(PfRestFeature.captivePortalVouchers);
    final generate =
        registry.decision(PfRestFeature.captivePortalVoucherGeneration);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captive Portal'),
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: session.connected
                ? () => session.refreshCapabilities()
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              icon: Icon(
                sessions.isUnsupported
                    ? Icons.extension_off_outlined
                    : Icons.people_outline,
              ),
              text: 'Sessions',
            ),
            Tab(
              icon: Icon(
                vouchers.isUnsupported && generate.isUnsupported
                    ? Icons.extension_off_outlined
                    : Icons.confirmation_number_outlined,
              ),
              text: 'Vouchers',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          sessions.isUnsupported
              ? PfRestFeatureBlockedView(
                  decision: sessions,
                  onRefresh: () => session.refreshCapabilities(),
                )
              : _SessionsTab(
                  readDecision: sessions,
                  disconnectDecision: disconnect,
                ),
          _VouchersTab(
            readDecision: vouchers,
            generateDecision: generate,
          ),
        ],
      ),
    );
  }
}

class _SessionsTab extends StatefulWidget {
  const _SessionsTab({
    required this.readDecision,
    required this.disconnectDecision,
  });

  final PfRestFeatureDecision readDecision;
  final PfRestFeatureDecision disconnectDecision;

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab>
    with AutomaticKeepAliveClientMixin {
  List<CaptivePortalSession> _sessions = [];
  String? _error;
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastRefresh;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (!changed) return;

    _requestGeneration++;
    _sessions = [];
    _error = null;
    _lastRefresh = null;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;
    if (session.connected && widget.readDecision.canAttempt) {
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
    if (_loading || !widget.readDecision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (mounted) setState(() => _error = 'Disconnected');
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
      final data = await session.service!.getCaptivePortalSessions();
      if (!mounted ||
          request != _requestGeneration ||
          generation != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _sessions = data;
        _error = null;
        _lastRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = pfRestFeatureRequestErrorMessage(
            PfRestFeature.captivePortalSessions,
            error,
          );
        });
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _disconnect(CaptivePortalSession portalSession) async {
    if (_actionBusy || !widget.disconnectDecision.canAttempt) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: Text(
          'Remove ${portalSession.displayName} (${portalSession.ipAddress}) from the captive portal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    setState(() => _actionBusy = true);
    try {
      await session.service!.disconnectCaptivePortalSession(
        ipAddress: portalSession.ipAddress,
        macAddress: portalSession.macAddress,
        zone: portalSession.zone.isEmpty ? null : portalSession.zone,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pfRestFeatureRequestErrorMessage(
                PfRestFeature.captivePortalDisconnect,
                error,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (widget.readDecision.isUnknown) ...[
            PfRestFeatureNotice(
              decision: widget.readDecision,
              onRefresh: () => session.refreshCapabilities(),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.disconnectDecision.isAvailable) ...[
            PfRestFeatureNotice(
              decision: widget.disconnectDecision,
              onRefresh: () => session.refreshCapabilities(),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(
                '${_sessions.length} active session${_sessions.length == 1 ? '' : 's'}',
              ),
              subtitle: Text(
                _lastRefresh == null
                    ? 'Pull to refresh'
                    : 'Last updated ${_formatTime(_lastRefresh!)}',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const StateMessage(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _error!,
              action: TextButton(
                onPressed: () => _load(showSpinner: true),
                child: const Text('Retry'),
              ),
            )
          else if (_sessions.isEmpty && !_loading)
            const StateMessage(
              icon: Icons.people_outline,
              text: 'No active sessions',
              details: 'No guests are currently connected.',
            )
          else
            for (final portalSession in _sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SessionTile(
                  session: portalSession,
                  busy: _actionBusy,
                  disconnectEnabled: widget.disconnectDecision.canAttempt,
                  onDisconnect: () => _disconnect(portalSession),
                ),
              ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.busy,
    required this.disconnectEnabled,
    required this.onDisconnect,
  });

  final CaptivePortalSession session;
  final bool busy;
  final bool disconnectEnabled;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(session.displayName),
        subtitle: Text(
          [
            session.ipAddress,
            if (session.macAddress.isNotEmpty) session.macAddress,
            if (session.zone.isNotEmpty) session.zone,
          ].join(' · '),
        ),
        trailing: IconButton(
          tooltip: disconnectEnabled
              ? 'Disconnect'
              : 'Disconnect endpoint unavailable',
          onPressed: disconnectEnabled && !busy ? onDisconnect : null,
          icon: const Icon(Icons.logout),
        ),
      ),
    );
  }
}

class _VouchersTab extends StatefulWidget {
  const _VouchersTab({
    required this.readDecision,
    required this.generateDecision,
  });

  final PfRestFeatureDecision readDecision;
  final PfRestFeatureDecision generateDecision;

  @override
  State<_VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<_VouchersTab>
    with AutomaticKeepAliveClientMixin {
  final _zoneController = TextEditingController(text: 'voucher');
  List<CaptivePortalVoucher> _vouchers = [];
  List<String> _newCodes = [];
  String? _error;
  bool _loading = false;
  bool _generating = false;
  int _generateCount = 5;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (!changed) return;

    _requestGeneration++;
    _vouchers = [];
    _newCodes = [];
    _error = null;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;
    if (session.connected && widget.readDecision.canAttempt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _zoneController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading || !widget.readDecision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (mounted) setState(() => _error = 'Disconnected');
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
      final data = await session.service!.getCaptivePortalVouchers(
        zone: _zoneController.text.trim().isEmpty
            ? null
            : _zoneController.text.trim(),
      );
      if (!mounted ||
          request != _requestGeneration ||
          generation != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _vouchers = data;
        _error = null;
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = pfRestFeatureRequestErrorMessage(
            PfRestFeature.captivePortalVouchers,
            error,
          );
        });
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generate() async {
    if (_generating || !widget.generateDecision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final zone = _zoneController.text.trim();
    if (zone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a zone name first.')),
      );
      return;
    }

    setState(() {
      _generating = true;
      _newCodes = [];
    });
    try {
      final codes = await session.service!.generateCaptivePortalVouchers(
        zone: zone,
        count: _generateCount,
      );
      if (mounted) setState(() => _newCodes = codes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pfRestFeatureRequestErrorMessage(
                PfRestFeature.captivePortalVoucherGeneration,
                error,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _share() {
    if (_newCodes.isEmpty) return;
    final text = 'Wi-Fi Access Vouchers\n\n'
        '${_newCodes.map((code) => '• $code').join('\n')}';
    Share.share(text, subject: 'Wi-Fi Access Vouchers');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();

    if (widget.readDecision.isUnsupported &&
        widget.generateDecision.isUnsupported) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PfRestFeatureNotice(
            decision: widget.readDecision,
            onRefresh: () => session.refreshCapabilities(),
          ),
          const SizedBox(height: 12),
          PfRestFeatureNotice(
            decision: widget.generateDecision,
            onRefresh: () => session.refreshCapabilities(),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (!widget.generateDecision.isAvailable) ...[
            PfRestFeatureNotice(
              decision: widget.generateDecision,
              onRefresh: () => session.refreshCapabilities(),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate vouchers',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _zoneController,
                    enabled: widget.generateDecision.canAttempt,
                    decoration: const InputDecoration(
                      labelText: 'Zone name',
                      hintText: 'voucher',
                      prefixIcon: Icon(Icons.wifi_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final count in const [1, 5, 10, 20])
                        ChoiceChip(
                          label: Text('$count'),
                          selected: _generateCount == count,
                          onSelected: widget.generateDecision.canAttempt
                              ? (_) => setState(() => _generateCount = count)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: widget.generateDecision.canAttempt &&
                                !_generating
                            ? _generate
                            : null,
                        icon: _generating
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.add_outlined),
                        label: Text(
                          _generating ? 'Generating…' : 'Generate',
                        ),
                      ),
                      if (_newCodes.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_newCodes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_newCodes.length} voucher${_newCodes.length == 1 ? '' : 's'} generated',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final code in _newCodes)
                      SelectableText(
                        code,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!widget.readDecision.isAvailable) ...[
            PfRestFeatureNotice(
              decision: widget.readDecision,
              onRefresh: () => session.refreshCapabilities(),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Existing vouchers (${_vouchers.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (widget.readDecision.isUnsupported)
            const StateMessage(
              icon: Icons.extension_off_outlined,
              text: 'Voucher listing unavailable',
              details: 'The listing endpoint is not reported by this firewall.',
            )
          else if (!session.connected)
            const StateMessage(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _error!,
            )
          else if (_vouchers.isEmpty && !_loading)
            const StateMessage(
              icon: Icons.confirmation_number_outlined,
              text: 'No vouchers found',
            )
          else
            for (final voucher in _vouchers)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: Text(
                    voucher.code,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: voucher.minutesRemaining == null
                      ? null
                      : Text('${voucher.minutesRemaining} min remaining'),
                  trailing: voucher.used
                      ? const Chip(label: Text('Used'))
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
