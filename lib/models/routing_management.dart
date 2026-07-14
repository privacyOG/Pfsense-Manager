import 'dart:collection';

import 'pfrest_capabilities.dart';

enum RoutingResourceKind {
  gateway(
    label: 'Gateways',
    singularLabel: 'gateway',
    collectionPath: '/api/v2/routing/gateways',
    itemPath: '/api/v2/routing/gateway',
  ),
  gatewayGroup(
    label: 'Gateway groups',
    singularLabel: 'gateway group',
    collectionPath: '/api/v2/routing/gateway/groups',
    itemPath: '/api/v2/routing/gateway/group',
  ),
  staticRoute(
    label: 'Static routes',
    singularLabel: 'static route',
    collectionPath: '/api/v2/routing/static_routes',
    itemPath: '/api/v2/routing/static_route',
  );

  const RoutingResourceKind({
    required this.label,
    required this.singularLabel,
    required this.collectionPath,
    required this.itemPath,
  });

  final String label;
  final String singularLabel;
  final String collectionPath;
  final String itemPath;
}

const routingDefaultGatewayPath = '/api/v2/routing/gateway/default';
const routingApplyPath = '/api/v2/routing/apply';
const routingFirewallRulesPath = '/api/v2/firewall/rules';

class RoutingResourceCapability {
  const RoutingResourceCapability({
    required this.kind,
    this.read,
    this.create,
    this.update,
    this.delete,
  });

  final RoutingResourceKind kind;
  final PfRestOperationCapability? read;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;

  bool get canRead => read != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null;
  bool get canDelete => delete != null;
}

class RoutingManagementCapabilities {
  RoutingManagementCapabilities._({
    required Map<RoutingResourceKind, RoutingResourceCapability> resources,
    required this.defaultRead,
    required this.defaultUpdate,
    required this.applyRead,
    required this.applyWrite,
    required this.firewallRuleRead,
  }) : resources = Map.unmodifiable(resources);

  factory RoutingManagementCapabilities.from(PfRestCapabilities? capabilities) {
    final resources = <RoutingResourceKind, RoutingResourceCapability>{};
    for (final kind in RoutingResourceKind.values) {
      resources[kind] = RoutingResourceCapability(
        kind: kind,
        read: capabilities?.operation(kind.collectionPath, 'GET'),
        create: capabilities?.operation(kind.itemPath, 'POST'),
        update: capabilities?.operation(kind.itemPath, 'PATCH'),
        delete: capabilities?.operation(kind.itemPath, 'DELETE'),
      );
    }
    return RoutingManagementCapabilities._(
      resources: resources,
      defaultRead: capabilities?.operation(routingDefaultGatewayPath, 'GET'),
      defaultUpdate:
          capabilities?.operation(routingDefaultGatewayPath, 'PATCH'),
      applyRead: capabilities?.operation(routingApplyPath, 'GET'),
      applyWrite: capabilities?.operation(routingApplyPath, 'POST'),
      firewallRuleRead:
          capabilities?.operation(routingFirewallRulesPath, 'GET'),
    );
  }

  final Map<RoutingResourceKind, RoutingResourceCapability> resources;
  final PfRestOperationCapability? defaultRead;
  final PfRestOperationCapability? defaultUpdate;
  final PfRestOperationCapability? applyRead;
  final PfRestOperationCapability? applyWrite;
  final PfRestOperationCapability? firewallRuleRead;

  RoutingResourceCapability forKind(RoutingResourceKind kind) =>
      resources[kind]!;

  List<RoutingResourceKind> get readableKinds => RoutingResourceKind.values
      .where((kind) => forKind(kind).canRead)
      .toList(growable: false);

  bool get canReadAnything =>
      readableKinds.isNotEmpty || defaultRead != null || applyRead != null;
  bool get canReadDefaults => defaultRead != null;
  bool get canUpdateDefaults => defaultUpdate != null;
  bool get canApply => applyWrite != null;
}

class ManagedRoutingResource {
  ManagedRoutingResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(_deepStringMap(raw));

  factory ManagedRoutingResource.fromJson(
    RoutingResourceKind kind,
    Map<String, dynamic> json,
  ) {
    return ManagedRoutingResource(kind: kind, raw: json);
  }

  final RoutingResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id => raw['id'] ?? raw['name'] ?? raw['network'];
  String get name => _text(raw['name']);
  String get description => _text(raw['descr'] ?? raw['description']);
  String get ipProtocol => _text(raw['ipprotocol']).toLowerCase();
  bool get disabled => _boolean(raw['disabled']);
  String get gatewayName => _text(raw['gateway']);

  List<Map<String, dynamic>> get priorities {
    final value = raw['priorities'];
    if (value is! List) return const [];
    return List.unmodifiable(
      value.whereType<Map>().map(
            (item) => item.map(
              (key, entry) => MapEntry(key.toString(), _copyValue(entry)),
            ),
          ),
    );
  }

  Set<String> get referencedGateways {
    if (kind == RoutingResourceKind.staticRoute) {
      return gatewayName.isEmpty ? const {} : {gatewayName};
    }
    if (kind != RoutingResourceKind.gatewayGroup) return const {};
    return Set.unmodifiable(
      priorities
          .map((priority) => _text(priority['gateway']))
          .where((gateway) => gateway.isNotEmpty),
    );
  }

  String get displayName {
    return switch (kind) {
      RoutingResourceKind.gateway || RoutingResourceKind.gatewayGroup =>
        name.isEmpty ? 'Unnamed ${kind.singularLabel}' : name,
      RoutingResourceKind.staticRoute =>
        _text(raw['network']).isEmpty
            ? 'Unnamed ${kind.singularLabel}'
            : _text(raw['network']),
    };
  }

  String get summary {
    return switch (kind) {
      RoutingResourceKind.gateway => [
          _text(raw['interface']),
          _text(raw['gateway']),
          ipProtocol == 'inet6' ? 'IPv6' : 'IPv4',
          disabled ? 'Disabled' : 'Enabled',
        ].where((item) => item.isNotEmpty).join(' • '),
      RoutingResourceKind.gatewayGroup => [
          _text(raw['trigger']),
          if (priorities.isNotEmpty)
            '${priorities.length} ${priorities.length == 1 ? 'gateway' : 'gateways'}',
          if (ipProtocol.isNotEmpty && ipProtocol != 'unknown')
            ipProtocol == 'inet6' ? 'IPv6' : 'IPv4',
        ].where((item) => item.isNotEmpty).join(' • '),
      RoutingResourceKind.staticRoute => [
          gatewayName,
          disabled ? 'Disabled' : 'Enabled',
        ].where((item) => item.isNotEmpty).join(' • '),
    };
  }

  Map<String, dynamic> writablePayload(
    PfRestOperationCapability operation, {
    Map<String, dynamic> changes = const {},
    bool includeIdentifier = false,
  }) {
    final payload = <String, dynamic>{};
    final bodyFields = operation.requestFields.values.where(
      (field) => field.location.toLowerCase() == 'body',
    );
    for (final field in bodyFields) {
      final name = field.name;
      if (changes.containsKey(name)) {
        payload[name] = _copyValue(changes[name]);
      } else if (raw.containsKey(name)) {
        payload[name] = _copyValue(raw[name]);
      }
    }

    if (includeIdentifier && id != null && !payload.containsKey('id')) {
      final idField = operation.field('id');
      if (idField == null || idField.location.toLowerCase() == 'body') {
        payload['id'] = _copyValue(id);
      }
    }
    return payload;
  }

  Map<String, dynamic> identifierQuery(PfRestOperationCapability operation) {
    final value = id;
    if (value == null) return const {};
    final field = operation.field('id', location: 'query');
    return field == null ? const {} : {'id': value.toString()};
  }
}

class RoutingDefaults {
  RoutingDefaults(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(_deepStringMap(raw));

  final Map<String, dynamic> raw;

  String get ipv4 => _text(raw['defaultgw4']);
  String get ipv6 => _text(raw['defaultgw6']);

  Map<String, dynamic> writablePayload(
    PfRestOperationCapability operation,
    Map<String, dynamic> changes,
  ) {
    final payload = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != 'body') continue;
      if (changes.containsKey(field.name)) {
        payload[field.name] = _copyValue(changes[field.name]);
      } else if (raw.containsKey(field.name)) {
        payload[field.name] = _copyValue(raw[field.name]);
      }
    }
    return payload;
  }
}

class GatewayDependencyReport {
  GatewayDependencyReport({
    this.gatewayGroups = const [],
    this.staticRoutes = const [],
    this.firewallRules = const [],
    this.defaultAssignments = const [],
    this.uncheckedSources = const {},
  })  : gatewayGroups = List.unmodifiable(gatewayGroups),
        staticRoutes = List.unmodifiable(staticRoutes),
        firewallRules = List.unmodifiable(firewallRules),
        defaultAssignments = List.unmodifiable(defaultAssignments),
        uncheckedSources = Set.unmodifiable(uncheckedSources);

  final List<String> gatewayGroups;
  final List<String> staticRoutes;
  final List<String> firewallRules;
  final List<String> defaultAssignments;
  final Set<String> uncheckedSources;

  bool get hasDependencies =>
      gatewayGroups.isNotEmpty ||
      staticRoutes.isNotEmpty ||
      firewallRules.isNotEmpty ||
      defaultAssignments.isNotEmpty;

  bool get complete => uncheckedSources.isEmpty;

  List<String> get descriptions => [
        for (final name in gatewayGroups) 'Gateway group: $name',
        for (final name in staticRoutes) 'Static route: $name',
        for (final name in firewallRules) 'Firewall rule: $name',
        for (final name in defaultAssignments) 'Default gateway: $name',
      ];
}

Map<String, dynamic> _deepStringMap(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, _copyValue(value)));
}

Object? _copyValue(Object? value) {
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), _copyValue(entry)));
  }
  if (value is List) return value.map(_copyValue).toList(growable: false);
  return value;
}

String _text(Object? value) => value?.toString().trim() ?? '';

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}
