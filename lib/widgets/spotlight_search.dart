import 'package:flutter/material.dart';

import '../models/dhcp_lease.dart';
import '../models/firewall_rule.dart';
import '../models/system_service.dart';
import '../services/pfsense_service.dart';

class _SpotlightResult {
  const _SpotlightResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
  });
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
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
      if (lease.ipAddress.contains(q) ||
          lease.macAddress.toLowerCase().contains(q) ||
          lease.hostname.toLowerCase().contains(q)) {
        results.add(_SpotlightResult(
          title: lease.hostname.isNotEmpty ? lease.hostname : lease.ipAddress,
          subtitle: '${lease.ipAddress} · ${lease.macAddress}',
          icon: Icons.router_outlined,
          category: 'DHCP',
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
        ));
      }
    }

    return results;
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
                  onTap: () => close(context, result),
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
