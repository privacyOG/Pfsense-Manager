import 'dart:collection';

import 'pfrest_capabilities.dart';

enum InterfaceResourceKind {
  assigned(
    label: 'Assigned',
    singularLabel: 'interface',
    collectionPath: '/api/v2/interfaces',
    itemPath: '/api/v2/interface',
  ),
  vlan(
    label: 'VLANs',
    singularLabel: 'VLAN',
    collectionPath: '/api/v2/interface/vlans',
    itemPath: '/api/v2/interface/vlan',
  ),
  bridge(
    label: 'Bridges',
    singularLabel: 'bridge',
    collectionPath: '/api/v2/interface/bridges',
    itemPath: '/api/v2/interface/bridge',
  ),
  lagg(
    label: 'LAGG',
    singularLabel: 'LAGG',
    collectionPath: '/api/v2/interface/laggs',
    itemPath: '/api/v2/interface/lagg',
  ),
  gre(
    label: 'GRE',
    singularLabel: 'GRE tunnel',
    collectionPath: '/api/v2/interface/gres',
    itemPath: '/api/v2/interface/gre',
  ),
  gif(
    label: 'GIF',
    singularLabel: 'GIF tunnel',
    collectionPath: '/api/v2/interface/gifs',
    itemPath: '/api/v2/interface/gif',
  );

  const InterfaceResourceKind({
    required this.label,
    required this.singularLabel,
    required this.collectionPath,
    required this.itemPath,
  });

  final String label;
  final String singularLabel;
  final String collectionPath;
  final String itemPath;

  bool get isAssigned => this == InterfaceResourceKind.assigned;
  bool get isVirtual => !isAssigned;
}

const interfaceAvailablePath = '/api/v2/interface/available_interfaces';
const interfaceApplyPath = '/api/v2/interface/apply';

class InterfaceResourceCapability {
  const InterfaceResourceCapability({
    required this.kind,
    this.read,
    this.create,
    this.update,
    this.delete,
  });

  final InterfaceResourceKind kind;
  final PfRestOperationCapability? read;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;

  bool get canRead => read != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null;
  bool get canDelete => delete != null;
  bool get hasAnyOperation => canRead || canCreate || canUpdate || canDelete;
}

class InterfaceManagementCapabilities {
  InterfaceManagementCapabilities._({
    required Map<InterfaceResourceKind, InterfaceResourceCapability> resources,
    required this.availableInterfaces,
    required this.apply,
  }) : resources = Map.unmodifiable(resources);

  factory InterfaceManagementCapabilities.from(
    PfRestCapabilities? capabilities,
  ) {
    final resources = <InterfaceResourceKind, InterfaceResourceCapability>{};
    for (final kind in InterfaceResourceKind.values) {
      resources[kind] = InterfaceResourceCapability(
        kind: kind,
        read: capabilities?.operation(kind.collectionPath, 'GET'),
        create: capabilities?.operation(kind.itemPath, 'POST'),
        update: capabilities?.operation(kind.itemPath, 'PATCH'),
        delete: capabilities?.operation(kind.itemPath, 'DELETE'),
      );
    }
    return InterfaceManagementCapabilities._(
      resources: resources,
      availableInterfaces:
          capabilities?.operation(interfaceAvailablePath, 'GET'),
      apply: capabilities?.operation(interfaceApplyPath, 'POST'),
    );
  }

  final Map<InterfaceResourceKind, InterfaceResourceCapability> resources;
  final PfRestOperationCapability? availableInterfaces;
  final PfRestOperationCapability? apply;

  InterfaceResourceCapability forKind(InterfaceResourceKind kind) =>
      resources[kind]!;

  List<InterfaceResourceKind> get readableKinds => InterfaceResourceKind.values
      .where((kind) => forKind(kind).canRead)
      .toList(growable: false);

  bool get canReadAnything => readableKinds.isNotEmpty;
  bool get canApply => apply != null;
}

class ManagedInterfaceResource {
  ManagedInterfaceResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(_deepStringMap(raw));

  factory ManagedInterfaceResource.fromJson(
    InterfaceResourceKind kind,
    Map<String, dynamic> json,
  ) {
    return ManagedInterfaceResource(kind: kind, raw: json);
  }

  final InterfaceResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id => raw['id'] ?? raw['uuid'] ?? raw['name'] ?? raw['descr'];
  String get interfaceName => _text(raw['if'] ?? raw['interface']);
  String get description => _text(raw['descr'] ?? raw['description']);
  bool get enabled => _bool(raw['enable'] ?? !(raw['disabled'] == true));
  String get ipv4Mode => _text(raw['typev4']).toLowerCase();
  String get ipv6Mode => _text(raw['typev6']).toLowerCase();
  String get ipv4Address => _text(raw['ipaddr']);
  String get ipv6Address => _text(raw['ipaddrv6']);
  int? get ipv4Prefix => _integer(raw['subnet']);
  int? get ipv6Prefix => _integer(raw['subnetv6']);

  String get displayName {
    final candidates = <Object?>[
      raw['descr'],
      raw['name'],
      raw['if'],
      raw['vlanif'],
      raw['bridgeif'],
      raw['laggif'],
      raw['greif'],
      raw['gifif'],
    ];
    for (final candidate in candidates) {
      final value = _text(candidate);
      if (value.isNotEmpty) return value;
    }
    final value = id?.toString().trim();
    return value == null || value.isEmpty
        ? 'Unnamed ${kind.singularLabel}'
        : value;
  }

  String get summary {
    switch (kind) {
      case InterfaceResourceKind.assigned:
        final addressing = <String>[];
        if (ipv4Mode.isNotEmpty) {
          addressing.add(ipv4Mode == 'static' && ipv4Address.isNotEmpty
              ? '$ipv4Address/${ipv4Prefix ?? '?'}'
              : 'IPv4 $ipv4Mode');
        }
        if (ipv6Mode.isNotEmpty && ipv6Mode != 'none') {
          addressing.add(ipv6Mode == 'static' && ipv6Address.isNotEmpty
              ? '$ipv6Address/${ipv6Prefix ?? '?'}'
              : 'IPv6 $ipv6Mode');
        }
        return [
          if (interfaceName.isNotEmpty) interfaceName,
          enabled ? 'Enabled' : 'Disabled',
          ...addressing,
        ].join(' • ');
      case InterfaceResourceKind.vlan:
        return _summaryValues(['if', 'tag', 'pcp']);
      case InterfaceResourceKind.bridge:
        return _summaryValues(['members', 'if', 'descr']);
      case InterfaceResourceKind.lagg:
        return _summaryValues(['laggproto', 'members', 'if']);
      case InterfaceResourceKind.gre:
      case InterfaceResourceKind.gif:
        return _summaryValues([
          'if',
          'parent',
          'local',
          'remote',
          'local_addr',
          'remote_addr',
        ]);
    }
  }

  Map<String, dynamic> writablePayload(
    PfRestOperationCapability operation, {
    Map<String, dynamic> changes = const {},
    bool includeIdentifier = false,
  }) {
    final payload = <String, dynamic>{};
    final bodyFields = operation.requestFields.values
        .where((field) => field.location.toLowerCase() == 'body')
        .toList(growable: false);

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
    final queryField = operation.field('id', location: 'query');
    if (queryField != null) return {'id': value.toString()};
    return const {};
  }

  String _summaryValues(List<String> names) {
    final values = <String>[];
    for (final name in names) {
      final value = raw[name];
      if (value is List && value.isNotEmpty) {
        values.add(value.map((item) => item.toString()).join(', '));
      } else {
        final text = _text(value);
        if (text.isNotEmpty && !values.contains(text)) values.add(text);
      }
      if (values.length == 3) break;
    }
    return values.isEmpty ? kind.singularLabel : values.join(' • ');
  }
}

class AvailableInterface {
  const AvailableInterface({
    required this.name,
    required this.description,
    required this.assigned,
  });

  factory AvailableInterface.fromJson(Map<String, dynamic> json) {
    return AvailableInterface(
      name: _text(json['if'] ?? json['name'] ?? json['interface']),
      description: _text(json['descr'] ?? json['description']),
      assigned: _bool(json['assigned'] ?? json['is_assigned']),
    );
  }

  final String name;
  final String description;
  final bool assigned;
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

String _text(Object? value) => value?.toString().trim() ?? '';

int? _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}
