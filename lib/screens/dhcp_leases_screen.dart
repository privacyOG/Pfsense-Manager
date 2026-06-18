import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dhcp_lease.dart';
import '../providers/session_provider.dart';
import '../widgets/state_message.dart';

class DhcpLeasesScreen extends StatefulWidget {
  const DhcpLeasesScreen({super.key});

  @override
  State<DhcpLeasesScreen> createState() => _DhcpLeasesScreenState();
}

class _DhcpLeasesScreenState extends State<DhcpLeasesScreen> {
  final _search = TextEditingController();
  List<DhcpLease> _leases = [];
  Object? _error;
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final sessionChanged = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;

    if (sessionChanged) {
      _requestGeneration++;
      _leases = [];
      _error = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_leases.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _leases = [];
        _lastSuccessfulRefresh = null;
        _error = 'Disconnected';
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
      final leases = await session.service!.getDhcpLeases();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _leases = leases;
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

  Future<void> _wake(DhcpLease lease) async {
    if (_actionBusy) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    setState(() => _actionBusy = true);
    try {
      await session.service!.sendWakeOnLan(lease.macAddress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Magic packet sent to ${lease.hostname.isNotEmpty ? lease.hostname : lease.macAddress}',
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
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _delete(DhcpLease lease) async {
    if (_actionBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete DHCP lease'),
        content: Text(
          'Remove ${lease.ipAddress.isEmpty ? lease.macAddress : lease.ipAddress} from the lease table?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    setState(() => _actionBusy = true);
    try {
      await session.service!.deleteDhcpLease(lease);
      await _load(showSpinner: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final query = _search.text.trim().toLowerCase();
    final visible = _leases
        .where((lease) =>
            query.isEmpty ||
            lease.ipAddress.toLowerCase().contains(query) ||
            lease.macAddress.toLowerCase().contains(query) ||
            lease.hostname.toLowerCase().contains(query) ||
            lease.interface.toLowerCase().contains(query))
        .toList();
    final active = _leases.where((lease) => lease.active).length;
    final staticCount = _leases.where((lease) => lease.staticMapping).length;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _LeaseSummary(
            total: session.connected ? _leases.length : 0,
            active: session.connected ? active : 0,
            staticCount: session.connected ? staticCount : 0,
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Search IP, MAC, hostname, interface',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const StateMessage(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _error.toString(),
            )
          else if (!_loading && visible.isEmpty)
            const StateMessage(
              icon: Icons.dns_outlined,
              text: 'No DHCP leases reported by pfREST.',
            ),
          if (session.connected)
            for (final lease in visible)
              _LeaseTile(
                lease: lease,
                onDelete: _actionBusy ? null : () => _delete(lease),
                onWake: (lease.macAddress.isNotEmpty && !_actionBusy)
                    ? () => _wake(lease)
                    : null,
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

class _LeaseSummary extends StatelessWidget {
  const _LeaseSummary({
    required this.total,
    required this.active,
    required this.staticCount,
  });

  final int total;
  final int active;
  final int staticCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.router_outlined, color: Color(0xFF00C2A8)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'DHCP Lease Management',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          _MiniStat('Active', active.toString()),
          _MiniStat('Static', staticCount.toString()),
          _MiniStat('Total', total.toString()),
        ],
      ),
    );
  }
}

class _LeaseTile extends StatelessWidget {
  const _LeaseTile({
    required this.lease,
    required this.onDelete,
    required this.onWake,
  });

  final DhcpLease lease;
  final VoidCallback? onDelete;
  final VoidCallback? onWake;

  @override
  Widget build(BuildContext context) {
    final color = lease.active ? const Color(0xFF00C2A8) : Colors.orangeAccent;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Icon(Icons.devices_other, color: color),
        ),
        title: Text(
          lease.hostname.isEmpty ? lease.ipAddress : lease.hostname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (lease.ipAddress.isNotEmpty) lease.ipAddress,
            if (lease.macAddress.isNotEmpty) lease.macAddress,
            if (lease.interface.isNotEmpty) lease.interface,
            lease.state,
          ].join('  |  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lease.macAddress.isNotEmpty)
              IconButton(
                tooltip: 'Wake on LAN',
                onPressed: onWake,
                icon: const Icon(Icons.power_settings_new_outlined),
              ),
            IconButton(
              tooltip: 'Delete lease',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
