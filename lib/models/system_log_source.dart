import 'dart:convert';

import 'package:flutter/material.dart';

const systemLogSchemaPath = '/api/v2/schema/openapi';

class SystemLogSource {
  const SystemLogSource({
    required this.id,
    required this.label,
    required this.path,
    required this.icon,
    this.isCustomExtension = false,
  });

  final String id;
  final String label;
  final String path;
  final IconData icon;
  final bool isCustomExtension;

  String get logType {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? id : segments.last;
  }
}

class _SystemLogDefinition {
  const _SystemLogDefinition({
    required this.id,
    required this.label,
    required this.slugs,
    required this.icon,
    this.isCustomExtension = false,
  });

  final String id;
  final String label;
  final Set<String> slugs;
  final IconData icon;
  final bool isCustomExtension;
}

const _systemLogDefinitions = <_SystemLogDefinition>[
  _SystemLogDefinition(
    id: 'system',
    label: 'System',
    slugs: {'system'},
    icon: Icons.dns_outlined,
  ),
  _SystemLogDefinition(
    id: 'dhcp',
    label: 'DHCP',
    slugs: {'dhcp', 'dhcpd'},
    icon: Icons.router_outlined,
  ),
  _SystemLogDefinition(
    id: 'authentication',
    label: 'Authentication',
    slugs: {'auth', 'authentication'},
    icon: Icons.verified_user_outlined,
  ),
  _SystemLogDefinition(
    id: 'openvpn',
    label: 'OpenVPN',
    slugs: {'openvpn'},
    icon: Icons.vpn_lock_outlined,
  ),
  _SystemLogDefinition(
    id: 'restapi',
    label: 'REST API',
    slugs: {'restapi', 'rest_api', 'rest-api', 'api'},
    icon: Icons.api_outlined,
  ),
  _SystemLogDefinition(
    id: 'resolver',
    label: 'DNS Resolver (custom)',
    slugs: {'resolver', 'unbound', 'dns_resolver', 'dns-resolver'},
    icon: Icons.travel_explore_outlined,
    isCustomExtension: true,
  ),
  _SystemLogDefinition(
    id: 'gateways',
    label: 'Gateway (custom)',
    slugs: {'gateway', 'gateways'},
    icon: Icons.swap_horiz_outlined,
    isCustomExtension: true,
  ),
];

List<SystemLogSource> systemLogSourcesFromOpenApi(dynamic document) {
  final root = _openApiRoot(document);
  final paths = _asMap(root?['paths']);
  if (paths == null || paths.isEmpty) return const [];

  final availablePaths = <String, String>{};
  for (final entry in paths.entries) {
    final path = entry.key.toString().trim();
    final operation = _asMap(entry.value);
    final slug = _systemLogSlug(path);
    if (slug == null || operation == null || !_supportsGet(operation)) continue;
    availablePaths.putIfAbsent(slug, () => path);
  }

  final result = <SystemLogSource>[];
  for (final definition in _systemLogDefinitions) {
    String? path;
    for (final slug in definition.slugs) {
      final candidate = availablePaths[slug];
      if (candidate != null) {
        path = candidate;
        break;
      }
    }
    if (path == null) continue;
    result.add(
      SystemLogSource(
        id: definition.id,
        label: definition.label,
        path: path,
        icon: definition.icon,
        isCustomExtension: definition.isCustomExtension,
      ),
    );
  }
  return List.unmodifiable(result);
}

Map<String, dynamic>? _openApiRoot(dynamic value) {
  dynamic decoded = value;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return null;
    }
  }

  final map = _asMap(decoded);
  if (map == null) return null;
  if (_asMap(map['paths']) != null) return map;
  if (map.containsKey('data')) return _openApiRoot(map['data']);
  return map;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

bool _supportsGet(Map<String, dynamic> operation) {
  return operation.keys.any((key) => key.toLowerCase() == 'get');
}

String? _systemLogSlug(String path) {
  final normalized = path
      .split('?')
      .first
      .trim()
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();
  const marker = '/status/logs/';
  final markerIndex = normalized.lastIndexOf(marker);
  if (markerIndex < 0) return null;
  final slug = normalized.substring(markerIndex + marker.length);
  if (slug.isEmpty || slug.contains('/')) return null;
  return slug;
}
