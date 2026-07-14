import 'dart:collection';

import 'pfrest_capabilities.dart';

enum VpnTechnology {
  openVpn(
    label: 'OpenVPN',
    serviceName: 'openvpn',
  ),
  ipsec(
    label: 'IPsec',
    serviceName: 'strongswan',
    applyPath: '/api/v2/vpn/ipsec/apply',
  ),
  wireGuard(
    label: 'WireGuard',
    serviceName: 'wireguard',
    applyPath: '/api/v2/vpn/wireguard/apply',
    settingsPath: '/api/v2/vpn/wireguard/settings',
  );

  const VpnTechnology({
    required this.label,
    required this.serviceName,
    this.applyPath,
    this.settingsPath,
  });

  final String label;
  final String serviceName;
  final String? applyPath;
  final String? settingsPath;

  bool get requiresExplicitApply => applyPath != null;
}

enum VpnResourceKind {
  openVpnServer(
    technology: VpnTechnology.openVpn,
    label: 'Servers',
    singularLabel: 'OpenVPN server',
    collectionPath: '/api/v2/vpn/openvpn/servers',
    itemPath: '/api/v2/vpn/openvpn/server',
  ),
  openVpnClient(
    technology: VpnTechnology.openVpn,
    label: 'Clients',
    singularLabel: 'OpenVPN client',
    collectionPath: '/api/v2/vpn/openvpn/clients',
    itemPath: '/api/v2/vpn/openvpn/client',
  ),
  openVpnCso(
    technology: VpnTechnology.openVpn,
    label: 'Client overrides',
    singularLabel: 'client-specific override',
    collectionPath: '/api/v2/vpn/openvpn/csos',
    itemPath: '/api/v2/vpn/openvpn/cso',
  ),
  openVpnExportConfig(
    technology: VpnTechnology.openVpn,
    label: 'Export defaults',
    singularLabel: 'client export default',
    collectionPath: '/api/v2/vpn/openvpn/client_export/configs',
    itemPath: '/api/v2/vpn/openvpn/client_export/config',
  ),
  ipsecPhase1(
    technology: VpnTechnology.ipsec,
    label: 'Phase 1',
    singularLabel: 'IPsec Phase 1 entry',
    collectionPath: '/api/v2/vpn/ipsec/phase1s',
    itemPath: '/api/v2/vpn/ipsec/phase1',
  ),
  ipsecPhase2(
    technology: VpnTechnology.ipsec,
    label: 'Phase 2',
    singularLabel: 'IPsec Phase 2 entry',
    collectionPath: '/api/v2/vpn/ipsec/phase2s',
    itemPath: '/api/v2/vpn/ipsec/phase2',
  ),
  wireGuardTunnel(
    technology: VpnTechnology.wireGuard,
    label: 'Tunnels',
    singularLabel: 'WireGuard tunnel',
    collectionPath: '/api/v2/vpn/wireguard/tunnels',
    itemPath: '/api/v2/vpn/wireguard/tunnel',
  ),
  wireGuardPeer(
    technology: VpnTechnology.wireGuard,
    label: 'Peers',
    singularLabel: 'WireGuard peer',
    collectionPath: '/api/v2/vpn/wireguard/peers',
    itemPath: '/api/v2/vpn/wireguard/peer',
  ),
  wireGuardTunnelAddress(
    technology: VpnTechnology.wireGuard,
    label: 'Tunnel addresses',
    singularLabel: 'WireGuard tunnel address',
    collectionPath: '/api/v2/vpn/wireguard/tunnel/addresses',
    itemPath: '/api/v2/vpn/wireguard/tunnel/address',
    child: true,
    parentKind: VpnResourceKind.wireGuardTunnel,
  ),
  wireGuardPeerAllowedIp(
    technology: VpnTechnology.wireGuard,
    label: 'Peer allowed IPs',
    singularLabel: 'WireGuard allowed IP',
    collectionPath: '/api/v2/vpn/wireguard/peer/allowed_ips',
    itemPath: '/api/v2/vpn/wireguard/peer/allowed_ip',
    child: true,
    parentKind: VpnResourceKind.wireGuardPeer,
  );

  const VpnResourceKind({
    required this.technology,
    required this.label,
    required this.singularLabel,
    required this.collectionPath,
    required this.itemPath,
    this.child = false,
    this.parentKind,
  });

  final VpnTechnology technology;
  final String label;
  final String singularLabel;
  final String collectionPath;
  final String itemPath;
  final bool child;
  final VpnResourceKind? parentKind;
}

const openVpnClientExportPath = '/api/v2/vpn/openvpn/client_export';

class VpnResourceCapability {
  const VpnResourceCapability({
    required this.kind,
    this.read,
    this.create,
    this.update,
    this.delete,
  });

  final VpnResourceKind kind;
  final PfRestOperationCapability? read;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;

  bool get canRead => read != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null;
  bool get canDelete => delete != null;
}

class VpnTechnologyCapabilities {
  const VpnTechnologyCapabilities({
    required this.technology,
    required this.resources,
    this.applyRead,
    this.applyWrite,
    this.settingsRead,
    this.settingsUpdate,
  });

  final VpnTechnology technology;
  final List<VpnResourceKind> resources;
  final PfRestOperationCapability? applyRead;
  final PfRestOperationCapability? applyWrite;
  final PfRestOperationCapability? settingsRead;
  final PfRestOperationCapability? settingsUpdate;

  bool get canApply =>
      !technology.requiresExplicitApply || applyWrite != null;
  bool get canReadAnything =>
      resources.isNotEmpty || settingsRead != null || applyRead != null;
}

class VpnManagementCapabilities {
  VpnManagementCapabilities._({
    required Map<VpnResourceKind, VpnResourceCapability> resources,
    required Map<VpnTechnology, VpnTechnologyCapabilities> technologies,
    this.clientExport,
  })  : resources = Map.unmodifiable(resources),
        technologies = Map.unmodifiable(technologies);

  factory VpnManagementCapabilities.from(PfRestCapabilities? capabilities) {
    final resources = <VpnResourceKind, VpnResourceCapability>{};
    for (final kind in VpnResourceKind.values) {
      resources[kind] = VpnResourceCapability(
        kind: kind,
        read: capabilities?.operation(kind.collectionPath, 'GET'),
        create: capabilities?.operation(kind.itemPath, 'POST'),
        update: capabilities?.operation(kind.itemPath, 'PATCH'),
        delete: capabilities?.operation(kind.itemPath, 'DELETE'),
      );
    }

    final technologies = <VpnTechnology, VpnTechnologyCapabilities>{};
    for (final technology in VpnTechnology.values) {
      final readableResources = VpnResourceKind.values
          .where(
            (kind) =>
                kind.technology == technology && resources[kind]!.canRead,
          )
          .toList(growable: false);
      technologies[technology] = VpnTechnologyCapabilities(
        technology: technology,
        resources: readableResources,
        applyRead: technology.applyPath == null
            ? null
            : capabilities?.operation(technology.applyPath!, 'GET'),
        applyWrite: technology.applyPath == null
            ? null
            : capabilities?.operation(technology.applyPath!, 'POST'),
        settingsRead: technology.settingsPath == null
            ? null
            : capabilities?.operation(technology.settingsPath!, 'GET'),
        settingsUpdate: technology.settingsPath == null
            ? null
            : capabilities?.operation(technology.settingsPath!, 'PATCH'),
      );
    }

    return VpnManagementCapabilities._(
      resources: resources,
      technologies: technologies,
      clientExport: capabilities?.operation(openVpnClientExportPath, 'POST'),
    );
  }

  final Map<VpnResourceKind, VpnResourceCapability> resources;
  final Map<VpnTechnology, VpnTechnologyCapabilities> technologies;
  final PfRestOperationCapability? clientExport;

  VpnResourceCapability forKind(VpnResourceKind kind) => resources[kind]!;
  VpnTechnologyCapabilities forTechnology(VpnTechnology technology) =>
      technologies[technology]!;

  List<VpnTechnology> get readableTechnologies => VpnTechnology.values
      .where((technology) => forTechnology(technology).canReadAnything)
      .toList(growable: false);

  bool get canReadAnything => readableTechnologies.isNotEmpty;
  bool get canExportOpenVpnClient => clientExport != null;
}

class ManagedVpnResource {
  ManagedVpnResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(_sanitiseVpnMap(raw));

  factory ManagedVpnResource.fromJson(
    VpnResourceKind kind,
    Map<String, dynamic> json,
  ) {
    return ManagedVpnResource(kind: kind, raw: json);
  }

  final VpnResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id {
    return raw['id'] ??
        switch (kind) {
          VpnResourceKind.openVpnServer ||
          VpnResourceKind.openVpnClient => raw['vpnid'],
          VpnResourceKind.ipsecPhase1 => raw['ikeid'],
          VpnResourceKind.wireGuardTunnel => raw['name'],
          _ => null,
        };
  }

  String get parentId => _text(raw['parent_id']);
  String get description => _text(
        raw['description'] ?? raw['descr'],
      );
  bool get disabled => _boolean(raw['disable'] ?? raw['disabled']) ||
      (raw.containsKey('enabled') && !_boolean(raw['enabled']));

  String get displayName {
    if (description.isNotEmpty) return description;
    return switch (kind) {
      VpnResourceKind.openVpnServer =>
        'OpenVPN server ${_text(raw['vpnid'] ?? raw['id'])}',
      VpnResourceKind.openVpnClient =>
        'OpenVPN client ${_text(raw['vpnid'] ?? raw['id'])}',
      VpnResourceKind.openVpnCso =>
        _text(raw['common_name']).isEmpty
            ? 'Unnamed client override'
            : _text(raw['common_name']),
      VpnResourceKind.openVpnExportConfig =>
        'Export default ${_text(raw['id'])}',
      VpnResourceKind.ipsecPhase1 =>
        _text(raw['remote_gateway']).isEmpty
            ? 'IPsec Phase 1 ${_text(raw['ikeid'] ?? raw['id'])}'
            : _text(raw['remote_gateway']),
      VpnResourceKind.ipsecPhase2 =>
        'Phase 2 ${_text(raw['localid_address'] ?? raw['id'])}',
      VpnResourceKind.wireGuardTunnel =>
        _text(raw['name']).isEmpty ? 'Unnamed tunnel' : _text(raw['name']),
      VpnResourceKind.wireGuardPeer =>
        _text(raw['endpoint']).isEmpty
            ? 'Dynamic peer ${_shortKey(raw['publickey'])}'
            : _text(raw['endpoint']),
      VpnResourceKind.wireGuardTunnelAddress =>
        _cidr(raw['address'] ?? raw['network'], raw['mask']),
      VpnResourceKind.wireGuardPeerAllowedIp =>
        _cidr(raw['address'] ?? raw['network'], raw['mask']),
    };
  }

  String get summary {
    return switch (kind) {
      VpnResourceKind.openVpnServer => [
          disabled ? 'Disabled' : 'Enabled',
          _text(raw['mode']),
          _text(raw['protocol']),
          if (_text(raw['local_port']).isNotEmpty)
            'Port ${_text(raw['local_port'])}',
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.openVpnClient => [
          disabled ? 'Disabled' : 'Enabled',
          _text(raw['server_addr']),
          if (_text(raw['server_port']).isNotEmpty)
            'Port ${_text(raw['server_port'])}',
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.openVpnCso => [
          _text(raw['server_list']),
          _text(raw['tunnel_network']),
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.openVpnExportConfig =>
        _text(raw['server']).isEmpty ? '' : 'Server ${_text(raw['server'])}',
      VpnResourceKind.ipsecPhase1 => [
          disabled ? 'Disabled' : 'Enabled',
          _text(raw['iketype']),
          _text(raw['authentication_method']),
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.ipsecPhase2 => [
          disabled ? 'Disabled' : 'Enabled',
          if (_text(raw['ikeid']).isNotEmpty) 'Phase 1 ${_text(raw['ikeid'])}',
          _text(raw['mode']),
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.wireGuardTunnel => [
          disabled ? 'Disabled' : 'Enabled',
          if (_text(raw['listenport']).isNotEmpty)
            'Port ${_text(raw['listenport'])}',
          _shortKey(raw['publickey']),
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.wireGuardPeer => [
          disabled ? 'Disabled' : 'Enabled',
          _text(raw['tun']),
          _shortKey(raw['publickey']),
        ].where((value) => value.isNotEmpty).join(' • '),
      VpnResourceKind.wireGuardTunnelAddress ||
      VpnResourceKind.wireGuardPeerAllowedIp =>
        parentId.isEmpty ? '' : 'Parent $parentId',
    };
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

class VpnSingletonSettings {
  VpnSingletonSettings(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(_sanitiseVpnMap(raw));

  final Map<String, dynamic> raw;
}

class VpnExportResult {
  const VpnExportResult({
    required this.filename,
    required this.data,
  });

  final String filename;
  final String data;
}

Map<String, dynamic> buildVpnWritePayload({
  required PfRestOperationCapability operation,
  Map<String, dynamic> existing = const {},
  Map<String, dynamic> changes = const {},
  Object? id,
  Object? parentId,
}) {
  final payload = <String, dynamic>{};
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body' || field.readOnly) continue;
    final name = field.name;
    if (isVpnSecretField(field)) {
      if (changes.containsKey(name) && !_isEmptySecret(changes[name])) {
        payload[name] = _copyValue(changes[name]);
      }
      continue;
    }
    if (changes.containsKey(name)) {
      payload[name] = _copyValue(changes[name]);
    } else if (existing.containsKey(name)) {
      payload[name] = _copyValue(existing[name]);
    }
  }

  if (id != null &&
      operation.field('id', location: 'body') case final idField? &&
      !idField.readOnly &&
      !payload.containsKey('id')) {
    payload['id'] = _copyValue(id);
  }
  if (parentId != null &&
      parentId.toString().trim().isNotEmpty &&
      operation.field('parent_id', location: 'body') case final parentField? &&
      !parentField.readOnly &&
      !payload.containsKey('parent_id')) {
    payload['parent_id'] = _copyValue(parentId);
  }

  for (final name in _runtimeOnlyVpnFields) {
    payload.remove(name);
  }
  return payload;
}

bool isVpnSecretField(PfRestFieldConstraint field) {
  if (field.writeOnly || field.format?.toLowerCase() == 'password') return true;
  return isVpnSecretFieldName(field.name);
}

bool isVpnSecretFieldName(String name) {
  final normalised = name.trim().toLowerCase();
  return _vpnSecretFields.contains(normalised) ||
      normalised.endsWith('_password') ||
      normalised.endsWith('_passwd') ||
      normalised.endsWith('_secret') ||
      normalised.endsWith('_private_key');
}

const _vpnSecretFields = <String>{
  'tls',
  'privatekey',
  'presharedkey',
  'pre_shared_key',
  'shared_key',
  'proxy_passwd',
  'auth_pass',
  'password',
  'passwd',
  'secret',
  'prv',
  'binary_data',
};

const _runtimeOnlyVpnFields = <String>{
  'runtime_status',
  'status',
  'running',
  'connected',
  'pending',
  'dirty',
  'changes_pending',
  'bytes_sent',
  'bytes_received',
  'latest_handshake',
};

Map<String, dynamic> _sanitiseVpnMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    if (isVpnSecretFieldName(entry.key) ||
        _runtimeOnlyVpnFields.contains(entry.key.toLowerCase())) {
      continue;
    }
    result[entry.key] = _copyValue(entry.value);
  }
  return result;
}

Object? _copyValue(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), _copyValue(item)));
  }
  if (value is List) return value.map(_copyValue).toList(growable: false);
  return value;
}

bool _isEmptySecret(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  return false;
}

String _shortKey(Object? value) {
  final text = _text(value);
  if (text.length <= 12) return text;
  return '${text.substring(0, 6)}…${text.substring(text.length - 6)}';
}

String _cidr(Object? address, Object? mask) {
  final value = _text(address);
  final prefix = _text(mask);
  if (value.isEmpty) return 'Unnamed network';
  return prefix.isEmpty || value.contains('/') ? value : '$value/$prefix';
}

String _text(Object? value) => value?.toString().trim() ?? '';

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}
