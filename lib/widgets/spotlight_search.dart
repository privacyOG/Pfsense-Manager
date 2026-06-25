import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dhcp_lease.dart';
import '../models/firewall_rule.dart';
import '../models/system_service.dart';
import '../services/pfsense_service.dart';

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.copyable = false});
  final String label;
  final String value;
  final bool copyable;
}

class _SpotlightResult {
  const _SpotlightResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    required this.details,
  });
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final List<_DetailRow> details;
}

class SpotlightSearchDelegate extends SearchDelegate<Object?> {
  SpotlightSearchDelegate({required this.service})
      : super(searchFieldLabel: 'Search IPs, MACs, rules, services…');

  final PfSenseService service;

  List<DhcpLease>? _leases;
  List<FirewallRule>? _rules;
  List<SystemService>? _services;
  Future<void>? _loadFuture;

  Future<void> _ensureLoaded() {
    _loadFuture ??= _loadData();
    return _loadFuture!;
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        service.getDhcpLeases(),
        service.getFirewallRules(),
        service.getServices(),
      ]);
      _leases = results[0] as List<DhcpLease>;
      _rules = results[1] as List<FirewallRule>;
      _services = results[2] as List<SystemService>;
    } catch (_) {
      _leases = [];
      _rules = [];
      _services = [];
    }
  }

  List<_SpotlightResult> _buildResults(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];

    final results = <_SpotlightResult>[];

    // DHCP leases
    for (final lease in (_leases ?? [])) {
      if (lease.ipAddress.toLowerCase().contains(q) ||
          lease.macAddress.toLowerCase().contains(q) ||
          lease.hostname.toLowerCase().contains(q)) {
        results.add(_SpotlightResult(
          title: lease.hostname.isNotEmpty ? lease.hostname : lease.ipAddress,
          subtitle: '${lease.ipAddress} · ${lease.macAddress}',
          icon: Icons.router_outlined,
          category: 'DHCP',
          details: [
            if (lease.hostname.isNotEmpty) _DetailRow('Hostname', lease.hostname),
            if (lease.ipAddress.isNotEmpty)
              _DetailRow('IP address', lease.ipAddress, copyable: true),
            if (lease.macAddress.isNotEmpty)
              _DetailRow('MAC address', lease.macAddress, copyable: true),
            if (lease.interface.isNotEmpty)
              _DetailRow('Interface', lease.interface),
            _DetailRow('State', lease.active ? 'Active' : lease.state),
            if (lease.staticMapping) const _DetailRow('Mapping', 'Static'),
            if (lease.ends.isNotEmpty) _DetailRow('Lease ends', lease.ends),
          ],
        ));
      }
    }

    // Firewall rules
    for (final rule in (_rules ?? [])) {
      if (rule.description.toLowerCase().contains(q) ||
          rule.sourceNetwork.toLowerCase().contains(q) ||
          rule.destinationNetwork.toLowerCase().contains(q) ||
          rule.interface.toLowerCase().contains(q)) {
        results.add(_SpotlightResult(
          title: rule.description.isNotEmpty
              ? rule.description
              : '${rule.type.toUpperCase()} rule',
          subtitle:
              '${rule.interface} · ${rule.sourceNetwork} → ${rule.destinationNetwork}',
          icon: Icons.shield_outlined,
          category: 'Firewall rule',
          details: [
            _DetailRow('Action', rule.type.toUpperCase()),
            _DetailRow('Status', rule.enabled ? 'Enabled' : 'Disabled'),
            if (rule.interface.isNotEmpty)
              _DetailRow('Interface', rule.interface),
            _DetailRow('Protocol', rule.protocol),
            _DetailRow('Source', rule.sourceNetwork, copyable: true),
            _DetailRow('Destination', rule.destinationNetwork, copyable: true),
            if (rule.portRange.isNotEmpty) _DetailRow('Port', rule.portRange),
            if (rule.description.isNotEmpty)
              _DetailRow('Description', rule.description),
          ],
        ));
      }
    }

    // Services
    for (final svc in (_services ?? [])) {
      if (svc.name.toLowerCase().contains(q) ||
          svc.displayName.toLowerCase().contains(q)) {
        results.add(_SpotlightResult(
          title: svc.displayName,
          subtitle: svc.running ? 'Running' : 'Stopped',
          icon: svc.running
              ? Icons.check_circle_outline
              : Icons.radio_button_unchecked,
          category: 'Service',
          details: [
            _DetailRow('Service', svc.displayName),
            if (svc.name != svc.displayName) _DetailRow('Name', svc.name),
            _DetailRow('Status', svc.running ? 'Running' : 'Stopped'),
            if (svc.pid != null && svc.pid!.isNotEmpty)
              _DetailRow('PID', svc.pid!),
          ],
        ));
      }
    }

    return results;
  }

  void _showDetail(BuildContext context, _SpotlightResult result) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ResultDetailSheet(result: result),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Search across DHCP leases, firewall rules and services',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return FutureBuilder<void>(
      future: _ensureLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = _buildResults(query);

        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'No results for "$query"',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        // Group by category
        final grouped = <String, List<_SpotlightResult>>{};
        for (final r in results) {
          grouped.putIfAbsent(r.category, () => []).add(r);
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  entry.key,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final result in entry.value)
                ListTile(
                  leading: Icon(result.icon),
                  title: Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDetail(context, result),
                ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${results.length} result${results.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResultDetailSheet extends StatelessWidget {
  const _ResultDetailSheet({required this.result});

  final _SpotlightResult result;

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$value copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(result.icon, color: scheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        result.category,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            for (final row in result.details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        row.label,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (row.copyable)
                      InkWell(
                        onTap: () => _copy(context, row.value),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
