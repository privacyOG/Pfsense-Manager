import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/captive_portal_session.dart';
import '../models/captive_portal_voucher.dart';
import '../providers/session_provider.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captive Portal'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Sessions'),
            Tab(icon: Icon(Icons.confirmation_number_outlined), text: 'Vouchers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _SessionsTab(),
          _VouchersTab(),
        ],
      ),
    );
  }
}

// ── Sessions ──────────────────────────────────────────────────────────────────

class _SessionsTab extends StatefulWidget {
  const _SessionsTab();
  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<CaptivePortalSession> _sessions = [];
  Object? _error;
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastRefresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final pid = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration || _loadedProfileId != pid;
    if (changed) {
      _requestGeneration++;
      _sessions = [];
      _error = null;
      _lastRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = pid;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(showSpinner: true); });
      }
    } else if (_sessions.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(showSpinner: true); });
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
      setState(() { _sessions = []; _error = 'Disconnected'; });
      return;
    }
    final req = ++_requestGeneration;
    final gen = session.sessionGeneration;
    final pid = session.selectedProfile?.id;
    setState(() { _loading = true; if (showSpinner) _error = null; });
    try {
      final data = await session.service!.getCaptivePortalSessions();
      if (!mounted || req != _requestGeneration || gen != session.sessionGeneration || pid != session.selectedProfile?.id) return;
      setState(() { _sessions = data; _error = null; _lastRefresh = DateTime.now(); });
    } catch (e) {
      if (mounted && req == _requestGeneration) setState(() => _error = e);
    } finally {
      if (mounted && req == _requestGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect(CaptivePortalSession s) async {
    if (_actionBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: Text('Remove ${s.displayName} (${s.ipAddress}) from the captive portal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    setState(() => _actionBusy = true);
    try {
      await session.service!.disconnectCaptivePortalSession(
        ipAddress: s.ipAddress,
        macAddress: s.macAddress,
        zone: s.zone.isNotEmpty ? s.zone : null,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
          _header(context),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const StateMessage(icon: Icons.cloud_off_outlined, text: 'Disconnected')
          else if (_error != null)
            StateMessage(icon: Icons.error_outline, text: _error.toString(), action: TextButton(onPressed: () => _load(showSpinner: true), child: const Text('Retry')))
          else if (_sessions.isEmpty && !_loading)
            const StateMessage(icon: Icons.people_outline, text: 'No active sessions', details: 'No guests are currently connected to the captive portal')
          else
            for (final s in _sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SessionTile(session: s, busy: _actionBusy, onDisconnect: () => _disconnect(s)),
              ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.people_outline, color: Theme.of(context).colorScheme.primary),
        title: Text('${_sessions.length} active session${_sessions.length == 1 ? '' : 's'}'),
        subtitle: Text(_lastRefresh == null ? 'Pull to refresh' : 'Last updated ${_formatTime(_lastRefresh!)}'),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}:${l.second.toString().padLeft(2,'0')}';
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.busy, required this.onDisconnect});
  final CaptivePortalSession session;
  final bool busy;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final uptime = session.uptime;
    final uptimeStr = uptime == null ? '' : _formatUptime(uptime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(session.displayName, style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(Icons.logout, size: 20),
                color: Theme.of(context).colorScheme.error,
                onPressed: busy ? null : onDisconnect,
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _Chip(Icons.router_outlined, session.ipAddress),
              if (session.macAddress.isNotEmpty) _Chip(Icons.device_hub_outlined, session.macAddress),
              if (uptimeStr.isNotEmpty) _Chip(Icons.timer_outlined, uptimeStr),
              if (session.zone.isNotEmpty) _Chip(Icons.wifi_outlined, session.zone),
            ]),
            if (session.bytesIn > 0 || session.bytesOut > 0) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.arrow_downward, size: 13, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 3),
                Text(_formatBytes(session.bytesIn), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 12),
                Icon(Icons.arrow_upward, size: 13, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 3),
                Text(_formatBytes(session.bytesOut), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatUptime(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ── Vouchers ─────────────────────────────────────────────────────────────────

class _VouchersTab extends StatefulWidget {
  const _VouchersTab();
  @override
  State<_VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<_VouchersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<CaptivePortalVoucher> _vouchers = [];
  List<String> _newCodes = [];
  Object? _error;
  bool _loading = false;
  bool _generating = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  final _zoneController = TextEditingController(text: 'voucher');
  int _generateCount = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final pid = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration || _loadedProfileId != pid;
    if (changed) {
      _requestGeneration++;
      _vouchers = [];
      _newCodes = [];
      _error = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = pid;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(showSpinner: true); });
      }
    } else if (_vouchers.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(showSpinner: true); });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _zoneController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() { _vouchers = []; _error = 'Disconnected'; });
      return;
    }
    final req = ++_requestGeneration;
    final gen = session.sessionGeneration;
    final pid = session.selectedProfile?.id;
    setState(() { _loading = true; if (showSpinner) _error = null; });
    try {
      final data = await session.service!.getCaptivePortalVouchers(
        zone: _zoneController.text.trim().isNotEmpty ? _zoneController.text.trim() : null,
      );
      if (!mounted || req != _requestGeneration || gen != session.sessionGeneration || pid != session.selectedProfile?.id) return;
      setState(() { _vouchers = data; _error = null; });
    } catch (e) {
      if (mounted && req == _requestGeneration) setState(() => _error = e);
    } finally {
      if (mounted && req == _requestGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final zone = _zoneController.text.trim();
    if (zone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a zone name first')));
      return;
    }
    setState(() { _generating = true; _newCodes = []; });
    try {
      final codes = await session.service!.generateCaptivePortalVouchers(
        zone: zone,
        count: _generateCount,
      );
      if (mounted) setState(() => _newCodes = codes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _share() {
    if (_newCodes.isEmpty) return;
    final text = 'Wi-Fi Access Vouchers\n\n${_newCodes.map((c) => '• $c').join('\n')}';
    Share.share(text, subject: 'Wi-Fi Access Vouchers');
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
          // Generate section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generate vouchers', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _zoneController,
                    decoration: const InputDecoration(
                      labelText: 'Zone name',
                      hintText: 'voucher',
                      prefixIcon: Icon(Icons.wifi_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Count: '),
                    for (final n in [1, 5, 10, 20])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('$n'),
                          selected: _generateCount == n,
                          onSelected: (_) => setState(() => _generateCount = n),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _generating ? null : _generate,
                      icon: _generating
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_outlined),
                      label: Text(_generating ? 'Generating…' : 'Generate'),
                    ),
                    if (_newCodes.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share'),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          // New codes result
          if (_newCodes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.check_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('${_newCodes.length} voucher${_newCodes.length == 1 ? '' : 's'} generated', style: Theme.of(context).textTheme.titleSmall),
                    ]),
                    const SizedBox(height: 10),
                    for (final code in _newCodes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          const Icon(Icons.confirmation_number_outlined, size: 16),
                          const SizedBox(width: 8),
                          Text(code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
          // Existing vouchers
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.list_outlined, size: 18),
            const SizedBox(width: 8),
            Text('Existing vouchers (${_vouchers.length})', style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const StateMessage(icon: Icons.cloud_off_outlined, text: 'Disconnected')
          else if (_error != null)
            StateMessage(icon: Icons.info_outline, text: 'Voucher list unavailable', details: 'This pfSense instance may not support voucher listing via the API')
          else if (_vouchers.isEmpty && !_loading)
            const StateMessage(icon: Icons.confirmation_number_outlined, text: 'No vouchers found', details: 'Generate some vouchers above or check the zone name')
          else
            for (final v in _vouchers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.confirmation_number_outlined,
                      color: v.used ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(v.code, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: v.minutesRemaining != null
                        ? Text('${v.minutesRemaining} min remaining')
                        : null,
                    trailing: v.used
                        ? Chip(label: const Text('Used'), backgroundColor: Theme.of(context).colorScheme.errorContainer)
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
