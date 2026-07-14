import 'dart:collection';

import 'pfrest_capabilities.dart';

enum DhcpResourceKind {
  server(
    label: 'DHCP servers',
    singularLabel: 'DHCP server',
    collectionPath: '/api/v2/services/dhcp_servers',
    itemPath: '/api/v2/services/dhcp_server',
  ),
  staticMapping(
    label: 'Static mappings',
    singularLabel: 'static mapping',
    collectionPath: '/api/v2/services/dhcp_server/static_mappings',
    itemPath: '/api/v2/services/dhcp_server/static_mapping',
  ),
  addressPool(
    label: 'Additional pools',
    singularLabel: 'address pool',
    collectionPath: '/api/v2/services/dhcp_server/address_pools',
    itemPath: '/api/v2/services/dhcp_server/address_pool',
  );

  const DhcpResourceKind({
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

const dhcpRelayPath = '/api/v2/services/dhcp_relay';
const dhcpBackendPath = '/api/v2/services/dhcp_server/backend';
const dhcpApplyPath = '/api/v2/services/dhcp_server/apply';
const dhcpLeasePath = '/api/v2/status/dhcp_server/leases';

class DhcpResourceCapability {
  const DhcpResourceCapability({
    required this.kind,
    this.read,
    this.create,
    this.update,
    this.delete,
  });

  final DhcpResourceKind kind;
  final PfRestOperationCapability? read;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;

  bool get canRead => read != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null;
  bool get canDelete => delete != null;
}

class DhcpManagementCapabilities {
  DhcpManagementCapabilities._({
    required Map<DhcpResourceKind, DhcpResourceCapability> resources,
    required this.relayRead,
    required this.relayUpdate,
    required this.backendUpdate,
    required this.applyRead,
    required this.applyWrite,
    required this.leaseRead,
    required this.leaseDelete,
    required this.dhcpV6Paths,
  }) : resources = Map.unmodifiable(resources);

  factory DhcpManagementCapabilities.from(PfRestCapabilities? capabilities) {
    final resources = <DhcpResourceKind, DhcpResourceCapability>{};
    for (final kind in DhcpResourceKind.values) {
      resources[kind] = DhcpResourceCapability(
        kind: kind,
        read: capabilities?.operation(kind.collectionPath, 'GET'),
        create: capabilities?.operation(kind.itemPath, 'POST'),
        update: capabilities?.operation(kind.itemPath, 'PATCH'),
        delete: capabilities?.operation(kind.itemPath, 'DELETE'),
      );
    }
    final v6Paths = capabilities?.operations.values
            .map((operation) => operation.path)
            .where((path) {
              final value = path.toLowerCase();
              return value.contains('dhcpv6') || value.contains('dhcp6');
            })
            .toSet() ??
        const <String>{};
    return DhcpManagementCapabilities._(
      resources: resources,
      relayRead: capabilities?.operation(dhcpRelayPath, 'GET'),
      relayUpdate: capabilities?.operation(dhcpRelayPath, 'PATCH'),
      backendUpdate: capabilities?.operation(dhcpBackendPath, 'PATCH'),
      applyRead: capabilities?.operation(dhcpApplyPath, 'GET'),
      applyWrite: capabilities?.operation(dhcpApplyPath, 'POST'),
      leaseRead: capabilities?.operation(dhcpLeasePath, 'GET'),
      leaseDelete: capabilities?.operation(dhcpLeasePath, 'DELETE'),
      dhcpV6Paths: Set.unmodifiable(v6Paths),
    );
  }

  final Map<DhcpResourceKind, DhcpResourceCapability> resources;
  final PfRestOperationCapability? relayRead;
  final PfRestOperationCapability? relayUpdate;
  final PfRestOperationCapability? backendUpdate;
  final PfRestOperationCapability? applyRead;
  final PfRestOperationCapability? applyWrite;
  final PfRestOperationCapability? leaseRead;
  final PfRestOperationCapability? leaseDelete;
  final Set<String> dhcpV6Paths;

  DhcpResourceCapability forKind(DhcpResourceKind kind) => resources[kind]!;

  List<DhcpResourceKind> get readableKinds => DhcpResourceKind.values
      .where((kind) => forKind(kind).canRead)
      .toList(growable: false);

  bool get canReadAnything => readableKinds.isNotEmpty || relayRead != null;
  bool get canReadRelay => relayRead != null;
  bool get canUpdateRelay => relayUpdate != null;
  bool get canSwitchBackend => backendUpdate != null;
  bool get canApply => applyWrite != null;
  bool get reportsDhcpV6 => dhcpV6Paths.isNotEmpty;
}

class ManagedDhcpResource {
  ManagedDhcpResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(_deepStringMap(raw));

  factory ManagedDhcpResource.fromJson(
    DhcpResourceKind kind,
    Map<String, dynamic> json,
  ) {
    return ManagedDhcpResource(kind: kind, raw: json);
  }

  final DhcpResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id => switch (kind) {
        DhcpResourceKind.server => raw['id'] ?? raw['interface'],
        DhcpResourceKind.staticMapping || DhcpResourceKind.addressPool =>
          raw['id'],
      };

  String get parentId => _text(raw['parent_id']);
  String get interfaceId => kind == DhcpResourceKind.server
      ? _text(raw['id'] ?? raw['interface'])
      : parentId;
  bool get enabled => _boolean(raw['enable']);
  String get description => _text(raw['descr'] ?? raw['description']);
  String get rangeFrom => _text(raw['range_from']);
  String get rangeTo => _text(raw['range_to']);
  String get macAddress => _text(raw['mac']);
  String get ipAddress => _text(raw['ipaddr']);
  String get hostname => _text(raw['hostname']);

  String get displayName {
    return switch (kind) {
      DhcpResourceKind.server => interfaceId.isEmpty
          ? 'Unnamed DHCP server'
          : interfaceId.toUpperCase(),
      DhcpResourceKind.staticMapping => hostname.isNotEmpty
          ? hostname
          : ipAddress.isNotEmpty
              ? ipAddress
              : macAddress.isNotEmpty
                  ? macAddress
                  : 'Unnamed static mapping',
      DhcpResourceKind.addressPool =>
        rangeFrom.isEmpty && rangeTo.isEmpty
            ? 'Unnamed address pool'
            : '$rangeFrom – $rangeTo',
    };
  }

  String get summary {
    return switch (kind) {
      DhcpResourceKind.server => [
          enabled ? 'Enabled' : 'Disabled',
          if (rangeFrom.isNotEmpty || rangeTo.isNotEmpty)
            '$rangeFrom – $rangeTo',
          _text(raw['domain']),
        ].where((value) => value.isNotEmpty).join(' • '),
      DhcpResourceKind.staticMapping => [
          ipAddress,
          macAddress,
          if (parentId.isNotEmpty) parentId.toUpperCase(),
        ].where((value) => value.isNotEmpty).join(' • '),
      DhcpResourceKind.addressPool => [
          if (parentId.isNotEmpty) parentId.toUpperCase(),
          _text(raw['domain']),
        ].where((value) => value.isNotEmpty).join(' • '),
    };
  }

  Map<String, dynamic> writablePayload(
    PfRestOperationCapability operation, {
    Map<String, dynamic> changes = const {},
    bool includeIdentifiers = false,
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

    if (includeIdentifiers) {
      final resourceId = id;
      if (resourceId != null &&
          operation.field('id', location: 'body') != null &&
          !payload.containsKey('id')) {
        payload['id'] = _copyValue(resourceId);
      }
      if (parentId.isNotEmpty &&
          operation.field('parent_id', location: 'body') != null &&
          !payload.containsKey('parent_id')) {
        payload['parent_id'] = parentId;
      }
    }
    return payload;
  }

  Map<String, dynamic> identifierQuery(PfRestOperationCapability operation) {
    final query = <String, dynamic>{};
    if (operation.field('parent_id', location: 'query') != null &&
        parentId.isNotEmpty) {
      query['parent_id'] = parentId;
    }
    final resourceId = id;
    if (operation.field('id', location: 'query') != null &&
        resourceId != null) {
      query['id'] = resourceId.toString();
    }
    return query;
  }
}

class DhcpSingletonConfiguration {
  DhcpSingletonConfiguration(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(_deepStringMap(raw));

  final Map<String, dynamic> raw;

  bool get enabled => _boolean(raw['enable']);
  List<String> get interfaces => _stringList(raw['interface']);
  List<String> get servers => _stringList(raw['server']);

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

Map<String, dynamic> _deepStringMap(Map<String, dynamic> source) {
  return source.map((key, value) => MapEntry(key, _copyValue(value)));
}

Object? _copyValue(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), _copyValue(item)));
  }
  if (value is List) return value.map(_copyValue).toList(growable: false);
  return value;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = _text(value);
  return text.isEmpty ? const [] : [text];
}

String _text(Object? value) => value?.toString().trim() ?? '';

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}
