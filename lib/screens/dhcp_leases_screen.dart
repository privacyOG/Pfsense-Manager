import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dhcp_lease.dart';
import '../providers/session_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_leases.isEmpty && !_loading) _load(showSpinner: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _error = 'Disconnected');
      return;
    }
    if (showSpinner) setState(() => _loading = true);
    try {
      final leases = await session.service!.getDhcpLeases();
      if (!mounted) return;
      setState(() {
        _leases = leases;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted && showSpinner) setState(() => _loading = false);
    }
  }

  Future<void> _delete(DhcpLease lease) async {
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
    try {
      await context.read<PfSenseSessionProvider>().service!.deleteDhcpLease(lease);
      await _load(showSpinner: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = _leases
        .where((lease) =>
            q.isEmpty ||
            lease.ipAddress.toLowerCase().contains(q) ||
            lease.macAddress.toLowerCase().contains(q) ||
            lease.hostname.toLowerCase().contains(q) ||
            lease.interface.toLowerCase().contains(q))
        .toList();
    final active = _leases.where((lease) => lease.active).length;
    final staticCount = _leases.where((lease) => lease.staticMapping).length;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _LeaseSummary(
            total: _leases.length,
            active: active,
            staticCount: staticCount,
          ),
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
          if (_error != null) _Message(icon: Icons.error_outline, text: '$_error'),
          if (!_loading && _error == null && visible.isEmpty)
            const _Message(
              icon: Icons.dns_outlined,
              text: 'No DHCP leases reported by pfREST.',
            ),
          for (final lease in visible)
            _LeaseTile(lease: lease, onDelete: () => _delete(lease)),
        ],
      ),
    );
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
  const _LeaseTile({required this.lease, required this.onDelete});

  final DhcpLease lease;
  final VoidCallback onDelete;

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
        trailing: IconButton(
          tooltip: 'Delete lease',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(leading: Icon(icon), title: Text(text)));
  }
}
