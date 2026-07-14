import 'dart:collection';

import 'pfrest_capabilities.dart';

enum DnsServiceKind {
  resolver(
    label: 'DNS Resolver',
    serviceName: 'unbound',
    applyPath: '/api/v2/services/dns_resolver/apply',
  ),
  forwarder(
    label: 'DNS Forwarder',
    serviceName: 'dnsmasq',
    applyPath: '/api/v2/services/dns_forwarder/apply',
  );

  const DnsServiceKind({
    required this.label,
    required this.serviceName,
    required this.applyPath,
  });

  final String label;
  final String serviceName;
  final String applyPath;
}

const dnsResolverSettingsPath = '/api/v2/services/dns_resolver/settings';

enum DnsResourceKind {
  resolverHostOverride(
    service: DnsServiceKind.resolver,
    label: 'Host overrides',
    singularLabel: 'host override',
    collectionPath: '/api/v2/services/dns_resolver/host_overrides',
    itemPath: '/api/v2/services/dns_resolver/host_override',
  ),
  resolverDomainOverride(
    service: DnsServiceKind.resolver,
    label: 'Domain overrides',
    singularLabel: 'domain override',
    collectionPath: '/api/v2/services/dns_resolver/domain_overrides',
    itemPath: '/api/v2/services/dns_resolver/domain_override',
  ),
  resolverAccessList(
    service: DnsServiceKind.resolver,
    label: 'Access lists',
    singularLabel: 'access list',
    collectionPath: '/api/v2/services/dns_resolver/access_lists',
    itemPath: '/api/v2/services/dns_resolver/access_list',
  ),
  resolverHostAlias(
    service: DnsServiceKind.resolver,
    label: 'Host aliases',
    singularLabel: 'host alias',
    collectionPath: '/api/v2/services/dns_resolver/host_override/aliases',
    itemPath: '/api/v2/services/dns_resolver/host_override/alias',
    child: true,
  ),
  resolverAccessListNetwork(
    service: DnsServiceKind.resolver,
    label: 'Access-list networks',
    singularLabel: 'access-list network',
    collectionPath: '/api/v2/services/dns_resolver/access_list/networks',
    itemPath: '/api/v2/services/dns_resolver/access_list/network',
    child: true,
  ),
  forwarderHostOverride(
    service: DnsServiceKind.forwarder,
    label: 'Host overrides',
    singularLabel: 'host override',
    collectionPath: '/api/v2/services/dns_forwarder/host_overrides',
    itemPath: '/api/v2/services/dns_forwarder/host_override',
  ),
  forwarderHostAlias(
    service: DnsServiceKind.forwarder,
    label: 'Host aliases',
    singularLabel: 'host alias',
    collectionPath: '/api/v2/services/dns_forwarder/host_override/aliases',
    itemPath: '/api/v2/services/dns_forwarder/host_override/alias',
    child: true,
  );

  const DnsResourceKind({
    required this.service,
    required this.label,
    required this.singularLabel,
    required this.collectionPath,
    required this.itemPath,
    this.child = false,
  });

  final DnsServiceKind service;
  final String label;
  final String singularLabel;
  final String collectionPath;
  final String itemPath;
  final bool child;
}

class DnsResourceCapability {
  const DnsResourceCapability({
    required this.kind,
    this.read,
    this.create,
    this.update,
    this.delete,
  });

  final DnsResourceKind kind;
  final PfRestOperationCapability? read;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;

  bool get canRead => read != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null;
  bool get canDelete => delete != null;
}

class DnsServiceCapabilities {
  const DnsServiceCapabilities({
    required this.service,
    required this.applyRead,
    required this.applyWrite,
    required this.resources,
  });

  final DnsServiceKind service;
  final PfRestOperationCapability? applyRead;
  final PfRestOperationCapability? applyWrite;
  final List<DnsResourceKind> resources;

  bool get canApply => applyWrite != null;
  bool get canReadAnything => resources.isNotEmpty || applyRead != null;
}

class DnsManagementCapabilities {
  DnsManagementCapabilities._({
    required Map<DnsResourceKind, DnsResourceCapability> resources,
    required Map<DnsServiceKind, DnsServiceCapabilities> services,
    required this.settingsRead,
    required this.settingsUpdate,
  })  : resources = Map.unmodifiable(resources),
        services = Map.unmodifiable(services);

  factory DnsManagementCapabilities.from(PfRestCapabilities? capabilities) {
    final resources = <DnsResourceKind, DnsResourceCapability>{};
    for (final kind in DnsResourceKind.values) {
      resources[kind] = DnsResourceCapability(
        kind: kind,
        read: capabilities?.operation(kind.collectionPath, 'GET'),
        create: capabilities?.operation(kind.itemPath, 'POST'),
        update: capabilities?.operation(kind.itemPath, 'PATCH'),
        delete: capabilities?.operation(kind.itemPath, 'DELETE'),
      );
    }
    final services = <DnsServiceKind, DnsServiceCapabilities>{};
    for (final service in DnsServiceKind.values) {
      final readable = DnsResourceKind.values
          .where(
            (kind) =>
                kind.service == service && resources[kind]!.canRead,
          )
          .toList(growable: false);
      services[service] = DnsServiceCapabilities(
        service: service,
        applyRead: capabilities?.operation(service.applyPath, 'GET'),
        applyWrite: capabilities?.operation(service.applyPath, 'POST'),
        resources: readable,
      );
    }
    return DnsManagementCapabilities._(
      resources: resources,
      services: services,
      settingsRead: capabilities?.operation(dnsResolverSettingsPath, 'GET'),
      settingsUpdate:
          capabilities?.operation(dnsResolverSettingsPath, 'PATCH'),
    );
  }

  final Map<DnsResourceKind, DnsResourceCapability> resources;
  final Map<DnsServiceKind, DnsServiceCapabilities> services;
  final PfRestOperationCapability? settingsRead;
  final PfRestOperationCapability? settingsUpdate;

  DnsResourceCapability forKind(DnsResourceKind kind) => resources[kind]!;
  DnsServiceCapabilities forService(DnsServiceKind service) =>
      services[service]!;

  List<DnsServiceKind> get readableServices => DnsServiceKind.values
      .where((service) {
        if (service == DnsServiceKind.resolver && settingsRead != null) {
          return true;
        }
        return forService(service).canReadAnything;
      })
      .toList(growable: false);

  bool get canReadSettings => settingsRead != null;
  bool get canUpdateSettings => settingsUpdate != null;
  bool get canReadAnything => readableServices.isNotEmpty;
}

class ManagedDnsResource {
  ManagedDnsResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(_deepStringMap(raw));

  factory ManagedDnsResource.fromJson(
    DnsResourceKind kind,
    Map<String, dynamic> json,
  ) {
    return ManagedDnsResource(kind: kind, raw: json);
  }

  final DnsResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id => raw['id'];
  String get parentId => _text(raw['parent_id']);
  String get description =>
      _text(raw['descr'] ?? raw['description']);
  String get host => _text(raw['host']);
  String get domain => _text(raw['domain']);
  String get name => _text(raw['name']);
  String get ip => _stringList(raw['ip']).join(', ');

  String get displayName {
    return switch (kind) {
      DnsResourceKind.resolverHostOverride ||
      DnsResourceKind.forwarderHostOverride => [host, domain]
          .where((value) => value.isNotEmpty)
          .join('.'),
      DnsResourceKind.resolverDomainOverride =>
        domain.isEmpty ? 'Unnamed domain override' : domain,
      DnsResourceKind.resolverAccessList =>
        name.isEmpty ? 'Unnamed access list' : name,
      DnsResourceKind.resolverHostAlias ||
      DnsResourceKind.forwarderHostAlias => [host, domain]
          .where((value) => value.isNotEmpty)
          .join('.'),
      DnsResourceKind.resolverAccessListNetwork =>
        '${_text(raw['network'])}/${_text(raw['mask'])}',
    };
  }

  String get summary {
    return switch (kind) {
      DnsResourceKind.resolverHostOverride ||
      DnsResourceKind.forwarderHostOverride => ip,
      DnsResourceKind.resolverDomainOverride => [
          _text(raw['ip']),
          _boolean(raw['forward_tls_upstream']) ? 'TLS upstream' : '',
        ].where((value) => value.isNotEmpty).join(' • '),
      DnsResourceKind.resolverAccessList => [
          _text(raw['action']),
          if (raw['networks'] is List)
            '${(raw['networks'] as List).length} networks',
        ].where((value) => value.isNotEmpty).join(' • '),
      DnsResourceKind.resolverHostAlias ||
      DnsResourceKind.forwarderHostAlias =>
        parentId.isEmpty ? '' : 'Parent #$parentId',
      DnsResourceKind.resolverAccessListNetwork =>
        parentId.isEmpty ? '' : 'Parent #$parentId',
    };
  }

  Map<String, dynamic> writablePayload(
    PfRestOperationCapability operation, {
    Map<String, dynamic> changes = const {},
    bool includeIdentifiers = false,
  }) {
    final payload = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != 'body') continue;
      if (changes.containsKey(field.name)) {
        payload[field.name] = _copyValue(changes[field.name]);
      } else if (raw.containsKey(field.name)) {
        payload[field.name] = _copyValue(raw[field.name]);
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

class DnsResolverSettings {
  DnsResolverSettings(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(_deepStringMap(raw));

  final Map<String, dynamic> raw;

  bool get enabled => _boolean(raw['enable']);
  bool get forwarding => _boolean(raw['forwarding']);
  bool get dnssec => _boolean(raw['dnssec']);
  int? get port => int.tryParse(_text(raw['port']));

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
