import 'package:flutter/material.dart';

class SystemLogSource {
  const SystemLogSource({
    required this.label,
    required this.logType,
    required this.icon,
  });

  final String label;
  final String logType;
  final IconData icon;
}

const systemLogSources = <SystemLogSource>[
  SystemLogSource(
    label: 'System',
    logType: 'system',
    icon: Icons.dns_outlined,
  ),
  SystemLogSource(
    label: 'DHCP',
    logType: 'dhcp',
    icon: Icons.router_outlined,
  ),
  SystemLogSource(
    label: 'DNS',
    logType: 'resolver',
    icon: Icons.travel_explore_outlined,
  ),
  SystemLogSource(
    label: 'Gateway',
    logType: 'gateways',
    icon: Icons.swap_horiz_outlined,
  ),
];

String systemLogPath(String logType) => '/api/v2/status/logs/$logType';
