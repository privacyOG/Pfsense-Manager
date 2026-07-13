import 'package:flutter/material.dart';

import 'interface_management_screen.dart';
import 'network_monitor/network_monitor_screen.dart' as live;

export 'network_monitor/network_monitor_screen.dart'
    show
        networkMonitorFormatRate,
        networkMonitorHistorySampleLimit,
        networkMonitorInterfacePollInterval,
        networkMonitorStatePollInterval;

class NetworkMonitorScreen extends StatelessWidget {
  const NetworkMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Live status and traffic counters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const Key('open-interface-management'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InterfaceManagementScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.settings_ethernet, size: 18),
                  label: const Text('Configure interfaces'),
                ),
              ],
            ),
          ),
        ),
        const Expanded(child: live.NetworkMonitorScreen()),
      ],
    );
  }
}
