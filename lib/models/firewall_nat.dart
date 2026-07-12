import 'dart:io';

enum FirewallNatRuleType {
  portForward,
  oneToOne,
  outboundMapping,
}

enum OutboundNatMode {
  automatic,
  hybrid,
  advanced,
  disabled;

  static OutboundNatMode parse(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    return OutboundNatMode.values.firstWhere(
      (mode) => mode.name == text,
      orElse: () => OutboundNatMode.automatic,
    );
  }

  String get label => switch (this) {
        OutboundNatMode.automatic => 'Automatic',
        OutboundNatMode.hybrid => 'Hybrid',
        OutboundNatMode.advanced => 'Manual',
        OutboundNatMode.disabled => 'Disabled',
      };

  String get description => switch (this) {
        OutboundNatMode.automatic =>
          'pfSense generates all outbound NAT mappings automatically.',
        OutboundNatMode.hybrid =>
          'Automatic mappings remain active and manual mappings are also allowed.',
        OutboundNatMode.advanced =>
          'Only manually configured outbound NAT mappings are used.',
        OutboundNatMode.disabled =>
          'Outbound NAT translation is disabled.',
      };
}

class NatPortForward {
  NatPortForward({
    this.id,
    required this.interface,
    required this.ipProtocol,
    required this.protocol,
    required this.source,
    this.sourcePort,
    required this.destination,
    this.destinationPort,
    required this.target,
    this.localPort,
    this.disabled = false,
    this.noRedirect = false,
    this.noSync = false,
    this.description = '',
    this.reflection,
    this.associatedRuleId = '',
    Map<String, dynamic> raw = const {},
  }) : raw = Map.unmodifiable(Map<String, dynamic>.from(raw));

  factory NatPortForward.fromJson(Map<String, dynamic> json) {
    return NatPortForward(
      id: _int(json['id']),
      interface: _text(json['interface']),
      ipProtocol: _text(json['ipprotocol'], fallback: 'inet'),
      protocol: _text(json['protocol'], fallback: 'tcp'),
      source: _text(json['source'], fallback: 'any'),
      sourcePort: _nullableText(json['source_port'] ?? json['sourceport']),
      destination: _text(json['destination'], fallback: 'any'),
      destinationPort:
          _nullableText(json['destination_port'] ?? json['destinationport']),
      target: _text(json['target']),
      localPort: _nullableText(json['local_port'] ?? json['local-port']),
      disabled: _bool(json['disabled']),
      noRedirect: _bool(json['nordr']),
      noSync: _bool(json['nosync']),
      description: _text(json['descr']),
      reflection: _nullableText(json['natreflection']),
      associatedRuleId: _text(
        json['associated_rule_id'] ?? json['associated-rule-id'],
      ),
      raw: json,
    );
  }

  final int? id;
  final String interface;
  final String ipProtocol;
  final String protocol;
  final String source;
  final String? sourcePort;
  final String destination;
  final String? destinationPort;
  final String target;
  final String? localPort;
  final bool disabled;
  final bool noRedirect;
  final bool noSync;
  final String description;
  final String? reflection;
  final String associatedRuleId;
  final Map<String, dynamic> raw;

  bool get enabled => !disabled;

  NatPortForward copyWith({
    int? id,
    String? interface,
    String? ipProtocol,
    String? protocol,
    String? source,
    String? sourcePort,
    bool clearSourcePort = false,
    String? destination,
    String? destinationPort,
    bool clearDestinationPort = false,
    String? target,
    String? localPort,
    bool clearLocalPort = false,
    bool? disabled,
    bool? noRedirect,
    bool? noSync,
    String? description,
    String? reflection,
    bool clearReflection = false,
    String? associatedRuleId,
  }) {
    return NatPortForward(
      id: id ?? this.id,
      interface: interface ?? this.interface,
      ipProtocol: ipProtocol ?? this.ipProtocol,
      protocol: protocol ?? this.protocol,
      source: source ?? this.source,
      sourcePort: clearSourcePort ? null : sourcePort ?? this.sourcePort,
      destination: destination ?? this.destination,
      destinationPort: clearDestinationPort
          ? null
          : destinationPort ?? this.destinationPort,
      target: target ?? this.target,
      localPort: clearLocalPort ? null : localPort ?? this.localPort,
      disabled: disabled ?? this.disabled,
      noRedirect: noRedirect ?? this.noRedirect,
      noSync: noSync ?? this.noSync,
      description: description ?? this.description,
      reflection: clearReflection ? null : reflection ?? this.reflection,
      associatedRuleId: associatedRuleId ?? this.associatedRuleId,
      raw: raw,
    );
  }

  Map<String, dynamic> toPayload({bool includeId = false}) {
    final payload = _editableRaw(raw);
    if (includeId && id != null) payload['id'] = id;
    payload
      ..['interface'] = interface.trim()
      ..['ipprotocol'] = ipProtocol
      ..['protocol'] = protocol
      ..['source'] = source.trim()
      ..['source_port'] = _emptyToNull(sourcePort)
      ..['destination'] = destination.trim()
      ..['destination_port'] = _emptyToNull(destinationPort)
      ..['target'] = target.trim()
      ..['local_port'] = _emptyToNull(localPort)
      ..['disabled'] = disabled
      ..['nordr'] = noRedirect
      ..['nosync'] = noSync
      ..['descr'] = description.trim()
      ..['natreflection'] = _emptyToNull(reflection)
      ..['associated_rule_id'] = associatedRuleId.trim();
    return payload;
  }
}

class NatOneToOneMapping {
  NatOneToOneMapping({
    this.id,
    required this.interface,
    this.disabled = false,
    this.noBinat = false,
    this.reflection,
    required this.ipProtocol,
    required this.external,
    required this.source,
    required this.destination,
    this.description = '',
    Map<String, dynamic> raw = const {},
  }) : raw = Map.unmodifiable(Map<String, dynamic>.from(raw));

  factory NatOneToOneMapping.fromJson(Map<String, dynamic> json) {
    return NatOneToOneMapping(
      id: _int(json['id']),
      interface: _text(json['interface']),
      disabled: _bool(json['disabled']),
      noBinat: _bool(json['nobinat']),
      reflection: _nullableText(json['natreflection']),
      ipProtocol: _text(json['ipprotocol'], fallback: 'inet'),
      external: _text(json['external']),
      source: _text(json['source'], fallback: 'any'),
      destination: _text(json['destination'], fallback: 'any'),
      description: _text(json['descr']),
      raw: json,
    );
  }

  final int? id;
  final String interface;
  final bool disabled;
  final bool noBinat;
  final String? reflection;
  final String ipProtocol;
  final String external;
  final String source;
  final String destination;
  final String description;
  final Map<String, dynamic> raw;

  bool get enabled => !disabled;

  NatOneToOneMapping copyWith({bool? disabled}) {
    return NatOneToOneMapping(
      id: id,
      interface: interface,
      disabled: disabled ?? this.disabled,
      noBinat: noBinat,
      reflection: reflection,
      ipProtocol: ipProtocol,
      external: external,
      source: source,
      destination: destination,
      description: description,
      raw: raw,
    );
  }

  Map<String, dynamic> toPayload({bool includeId = false}) {
    final payload = _editableRaw(raw);
    if (includeId && id != null) payload['id'] = id;
    payload
      ..['interface'] = interface.trim()
      ..['disabled'] = disabled
      ..['nobinat'] = noBinat
      ..['natreflection'] = _emptyToNull(reflection)
      ..['ipprotocol'] = ipProtocol
      ..['external'] = external.trim()
      ..['source'] = source.trim()
      ..['destination'] = destination.trim()
      ..['descr'] = description.trim();
    return payload;
  }
}

class NatOutboundMapping {
  NatOutboundMapping({
    this.id,
    required this.interface,
    this.protocol,
    this.disabled = false,
    this.noNat = false,
    this.noSync = false,
    required this.source,
    this.sourcePort,
    required this.destination,
    this.destinationPort,
    this.target,
    this.targetSubnet,
    this.natPort,
    this.staticNatPort = false,
    this.poolOptions,
    this.sourceHashKey,
    this.description = '',
    Map<String, dynamic> raw = const {},
  }) : raw = Map.unmodifiable(Map<String, dynamic>.from(raw));

  factory NatOutboundMapping.fromJson(Map<String, dynamic> json) {
    return NatOutboundMapping(
      id: _int(json['id']),
      interface: _text(json['interface']),
      protocol: _nullableText(json['protocol']),
      disabled: _bool(json['disabled']),
      noNat: _bool(json['nonat']),
      noSync: _bool(json['nosync']),
      source: _text(json['source'], fallback: 'any'),
      sourcePort: _nullableText(json['source_port'] ?? json['sourceport']),
      destination: _text(json['destination'], fallback: 'any'),
      destinationPort:
          _nullableText(json['destination_port'] ?? json['dstport']),
      target: _nullableText(json['target']),
      targetSubnet: _int(json['target_subnet']),
      natPort: _nullableText(json['nat_port'] ?? json['natport']),
      staticNatPort: _bool(json['static_nat_port'] ?? json['staticnatport']),
      poolOptions: _nullableText(json['poolopts']),
      sourceHashKey: _nullableText(json['source_hash_key']),
      description: _text(json['descr']),
      raw: json,
    );
  }

  final int? id;
  final String interface;
  final String? protocol;
  final bool disabled;
  final bool noNat;
  final bool noSync;
  final String source;
  final String? sourcePort;
  final String destination;
  final String? destinationPort;
  final String? target;
  final int? targetSubnet;
  final String? natPort;
  final bool staticNatPort;
  final String? poolOptions;
  final String? sourceHashKey;
  final String description;
  final Map<String, dynamic> raw;

  bool get enabled => !disabled;

  NatOutboundMapping copyWith({bool? disabled}) {
    return NatOutboundMapping(
      id: id,
      interface: interface,
      protocol: protocol,
      disabled: disabled ?? this.disabled,
      noNat: noNat,
      noSync: noSync,
      source: source,
      sourcePort: sourcePort,
      destination: destination,
      destinationPort: destinationPort,
      target: target,
      targetSubnet: targetSubnet,
      natPort: natPort,
      staticNatPort: staticNatPort,
      poolOptions: poolOptions,
      sourceHashKey: sourceHashKey,
      description: description,
      raw: raw,
    );
  }

  Map<String, dynamic> toPayload({bool includeId = false}) {
    final payload = _editableRaw(raw);
    final effectiveTargetSubnet =
        noNat ? null : targetSubnet ?? _defaultTargetSubnet(target);
    if (includeId && id != null) payload['id'] = id;
    payload
      ..['interface'] = interface.trim()
      ..['protocol'] = _emptyToNull(protocol)
      ..['disabled'] = disabled
      ..['nonat'] = noNat
      ..['nosync'] = noSync
      ..['source'] = source.trim()
      ..['source_port'] = _emptyToNull(sourcePort)
      ..['destination'] = destination.trim()
      ..['destination_port'] = _emptyToNull(destinationPort)
      ..['target'] = noNat ? null : _emptyToNull(target)
      ..['target_subnet'] = effectiveTargetSubnet
      ..['nat_port'] = noNat || staticNatPort ? null : _emptyToNull(natPort)
      ..['static_nat_port'] = noNat ? false : staticNatPort
      ..['poolopts'] = noNat ? null : _emptyToNull(poolOptions)
      ..['source_hash_key'] = noNat || poolOptions != 'source-hash'
          ? null
          : _emptyToNull(sourceHashKey)
      ..['descr'] = description.trim();
    return payload;
  }
}

Map<String, dynamic> _editableRaw(Map<String, dynamic> raw) {
  final payload = Map<String, dynamic>.from(raw);
  for (final key in const [
    'id',
    'created_time',
    'created_by',
    'updated_time',
    'updated_by',
    'created',
    'updated',
  ]) {
    payload.remove(key);
  }
  return payload;
}

int _defaultTargetSubnet(String? target) {
  final address = InternetAddress.tryParse(target?.trim() ?? '');
  return address?.type == InternetAddressType.IPv4 ? 32 : 128;
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text.toLowerCase() == 'null'
      ? fallback
      : text;
}

String? _nullableText(dynamic value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

Object? _emptyToNull(Object? value) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  return value is String ? value.trim() : value;
}

int? _int(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}
