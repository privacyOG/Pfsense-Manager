import '../models/pfrest_capabilities.dart';
import '../utils/firewall_port_validation.dart';

/// Complete writable pfREST firewall-rule representation.
///
/// The constructor keeps the original basic named parameters for compatibility,
/// while [interfaces], [sourcePort] and [destinationPort] preserve the richer
/// API representation used by floating rules, aliases and port ranges.
class FirewallRule {
  static const Object _copyUnset = Object();

  FirewallRule({
    this.id,
    this.section = 'rules',
    this.type = 'pass',
    String interface = '',
    List<String>? interfaces,
    this.ipProtocol = 'inet',
    String? protocol,
    this.icmpTypes = const ['any'],
    this.sourceType = 'network',
    this.sourceNetwork = 'any',
    this.sourceInverted = false,
    String? sourcePort,
    int? sourcePortFrom,
    int? sourcePortTo,
    this.destinationType = 'network',
    this.destinationNetwork = 'any',
    this.destinationInverted = false,
    String? destinationPort,
    int? destinationPortFrom,
    int? destinationPortTo,
    this.description = '',
    this.enabled = true,
    this.log = false,
    this.tag = '',
    this.stateType = 'keep state',
    this.tcpFlagsAny = false,
    this.tcpFlagsOutOf = const [],
    this.tcpFlagsSet = const [],
    this.gateway,
    this.schedule,
    this.dnpipe,
    this.pdnpipe,
    this.defaultQueue,
    this.ackQueue,
    this.floating = false,
    this.quick = false,
    this.direction = 'any',
    this.placement,
    this.tracker,
    this.associatedRuleId,
    this.createdTime = '',
    this.createdBy = '',
    this.updatedTime = '',
    this.updatedBy = '',
  })  : interfaces = List.unmodifiable(
          _normalizeInterfaces(interfaces, interface),
        ),
        _protocol = _normalizeProtocol(protocol),
        sourcePort = _normalizePortSpec(
          sourcePort ?? _portSpecFromNumbers(sourcePortFrom, sourcePortTo),
        ),
        destinationPort = _normalizePortSpec(
          destinationPort ??
              _portSpecFromNumbers(destinationPortFrom, destinationPortTo),
        );

  final String? id;
  final String section;
  final String type;
  final List<String> interfaces;
  final String ipProtocol;
  final String? _protocol;
  final List<String> icmpTypes;
  final String sourceType;
  final String sourceNetwork;
  final bool sourceInverted;
  final String? sourcePort;
  final String destinationType;
  final String destinationNetwork;
  final bool destinationInverted;
  final String? destinationPort;
  final String description;
  final bool enabled;
  final bool log;
  final String tag;
  final String stateType;
  final bool tcpFlagsAny;
  final List<String> tcpFlagsOutOf;
  final List<String> tcpFlagsSet;
  final String? gateway;
  final String? schedule;
  final String? dnpipe;
  final String? pdnpipe;
  final String? defaultQueue;
  final String? ackQueue;
  final bool floating;
  final bool quick;
  final String direction;

  /// Optional pfREST common control parameter used to insert or move a rule.
  final int? placement;

  final String? tracker;
  final String? associatedRuleId;
  final String createdTime;
  final String createdBy;
  final String updatedTime;
  final String updatedBy;

  factory FirewallRule.fromJson(Map<String, dynamic> json) {
    final source = _parseAddress(json['source_network'] ?? json['source']);
    final destination =
        _parseAddress(json['destination_network'] ?? json['destination']);
    final created = _map(json['created']);
    final updated = _map(json['updated']);

    return FirewallRule(
      id: (json['id'] ?? json['uuid'])?.toString(),
      section: json['section']?.toString() ?? 'rules',
      type: _lower(json['type'], fallback: 'pass'),
      interfaces: _stringList(json['interface']),
      ipProtocol: _lower(json['ipprotocol'], fallback: 'inet'),
      protocol: json['protocol']?.toString(),
      icmpTypes: _stringList(json['icmptype'], fallback: const ['any']),
      sourceType: json['source_type']?.toString() ?? 'network',
      sourceNetwork: source.value,
      sourceInverted: source.inverted,
      sourcePort: json['source_port']?.toString(),
      destinationType: json['destination_type']?.toString() ?? 'network',
      destinationNetwork: destination.value,
      destinationInverted: destination.inverted,
      destinationPort: json['destination_port']?.toString() ??
          _portSpecFromNumbers(
            _int(json['dst_port_from']),
            _int(json['dst_port_to']),
          ),
      description: (json['descr'] ?? json['description'])?.toString() ?? '',
      enabled: !_bool(json['disabled']),
      log: _bool(json['log']),
      tag: json['tag']?.toString() ?? '',
      stateType: json['statetype']?.toString() ?? 'keep state',
      tcpFlagsAny: _bool(json['tcp_flags_any'] ?? json['tcpflags_any']),
      tcpFlagsOutOf:
          _stringList(json['tcp_flags_out_of'] ?? json['tcpflags2']),
      tcpFlagsSet: _stringList(json['tcp_flags_set'] ?? json['tcpflags1']),
      gateway: _nullableText(json['gateway']),
      schedule: _nullableText(json['sched'] ?? json['schedule']),
      dnpipe: _nullableText(json['dnpipe']),
      pdnpipe: _nullableText(json['pdnpipe']),
      defaultQueue: _nullableText(json['defaultqueue']),
      ackQueue: _nullableText(json['ackqueue']),
      floating: _bool(json['floating']),
      quick: _bool(json['quick']),
      direction: json['direction']?.toString() ?? 'any',
      placement: _int(json['placement']),
      tracker: _nullableText(json['tracker']),
      associatedRuleId: _nullableText(
        json['associated_rule_id'] ?? json['associated-rule-id'],
      ),
      createdTime: json['created_time']?.toString() ??
          created?['time']?.toString() ??
          created?['utc']?.toString() ??
          '',
      createdBy:
          json['created_by']?.toString() ?? created?['username']?.toString() ?? '',
      updatedTime: json['updated_time']?.toString() ??
          updated?['time']?.toString() ??
          updated?['utc']?.toString() ??
          '',
      updatedBy:
          json['updated_by']?.toString() ?? updated?['username']?.toString() ?? '',
    );
  }

  /// Backward-compatible create payload.
  Map<String, dynamic> toJson() => toCreatePayload();

  Map<String, dynamic> toCreatePayload({
    PfRestOperationCapability? operation,
  }) {
    return _payload(
      operation: operation,
      includeNullOptionals: false,
      includeFloating: true,
    );
  }

  Map<String, dynamic> toUpdatePayload({
    PfRestOperationCapability? operation,
  }) {
    return _payload(
      operation: operation,
      includeNullOptionals: true,
      includeFloating: false,
    );
  }

  Map<String, dynamic> _payload({
    required PfRestOperationCapability? operation,
    required bool includeNullOptionals,
    required bool includeFloating,
  }) {
    final fields = operation?.requestFields.values
        .where((field) => field.location == 'body')
        .map((field) => field.name)
        .toSet();
    bool supports(String name) => fields == null || fields.contains(name);

    final payload = <String, dynamic>{};
    void requiredField(String name, Object? value) {
      if (supports(name)) payload[name] = value;
    }

    void optionalField(String name, Object? value) {
      if (!supports(name)) return;
      if (value != null || includeNullOptionals) payload[name] = value;
    }

    requiredField('type', type.trim().toLowerCase());
    requiredField('interface', interfaces);
    requiredField('ipprotocol', _resolveIpProtocol());
    optionalField('protocol', _protocol);

    if (_protocol == 'icmp' && _resolveIpProtocol() == 'inet') {
      optionalField(
        'icmptype',
        icmpTypes.isEmpty ? const ['any'] : List<String>.from(icmpTypes),
      );
    } else if (includeNullOptionals) {
      optionalField('icmptype', null);
    }

    requiredField('source', _apiAddress(sourceNetwork, sourceInverted));
    optionalField(
      'source_port',
      firewallProtocolSupportsPorts(_protocol) ? sourcePort : null,
    );
    requiredField(
      'destination',
      _apiAddress(destinationNetwork, destinationInverted),
    );
    optionalField(
      'destination_port',
      firewallProtocolSupportsPorts(_protocol) ? destinationPort : null,
    );
    requiredField('descr', description.trim());
    requiredField('disabled', !enabled);
    requiredField('log', log);
    requiredField('tag', tag.trim());
    requiredField('statetype', stateType.trim().toLowerCase());

    if (_protocol == 'tcp') {
      requiredField('tcp_flags_any', tcpFlagsAny);
      optionalField(
        'tcp_flags_out_of',
        tcpFlagsAny ? null : List<String>.from(tcpFlagsOutOf),
      );
      optionalField(
        'tcp_flags_set',
        tcpFlagsAny ? null : List<String>.from(tcpFlagsSet),
      );
    } else if (includeNullOptionals) {
      optionalField('tcp_flags_any', false);
      optionalField('tcp_flags_out_of', null);
      optionalField('tcp_flags_set', null);
    }

    optionalField('gateway', _nullableText(gateway));
    optionalField('sched', _nullableText(schedule));
    optionalField('dnpipe', _nullableText(dnpipe));
    optionalField('pdnpipe', _nullableText(pdnpipe));
    optionalField('defaultqueue', _nullableText(defaultQueue));
    optionalField('ackqueue', _nullableText(ackQueue));

    if (includeFloating) requiredField('floating', floating);
    if (floating) {
      requiredField('quick', quick);
      requiredField('direction', direction.trim().toLowerCase());
    } else if (includeNullOptionals) {
      optionalField('quick', false);
      optionalField('direction', 'any');
    }

    if (placement != null) payload['placement'] = placement;
    return payload;
  }

  String get interface => interfaces.join(', ');
  String get protocol => _protocol ?? 'any';
  String? get apiProtocol => _protocol;
  String get protocolLabel => protocol.toUpperCase();

  int? get sourcePortFrom => _numericPortRange(sourcePort).$1;
  int? get sourcePortTo => _numericPortRange(sourcePort).$2;
  int? get destinationPortFrom => _numericPortRange(destinationPort).$1;
  int? get destinationPortTo => _numericPortRange(destinationPort).$2;

  String get sourcePortRange => _displayPort(sourcePort);
  String get portRange => _displayPort(destinationPort);

  String get typeIcon => switch (type.toLowerCase()) {
        'pass' => 'PASS',
        'block' => 'BLOCK',
        'reject' => 'REJECT',
        _ => '?',
      };

  String _resolveIpProtocol() {
    final value = ipProtocol.trim().toLowerCase();
    if (value == 'inet' || value == 'inet6' || value == 'inet46') return value;
    if (_looksIpv6(sourceNetwork) || _looksIpv6(destinationNetwork)) {
      return 'inet6';
    }
    return 'inet';
  }

  FirewallRule copyWith({
    String? id,
    String? section,
    String? type,
    String? interface,
    List<String>? interfaces,
    String? ipProtocol,
    Object? protocol = _copyUnset,
    List<String>? icmpTypes,
    String? sourceType,
    String? sourceNetwork,
    bool? sourceInverted,
    Object? sourcePort = _copyUnset,
    String? destinationType,
    String? destinationNetwork,
    bool? destinationInverted,
    Object? destinationPort = _copyUnset,
    String? description,
    bool? enabled,
    bool? log,
    String? tag,
    String? stateType,
    bool? tcpFlagsAny,
    List<String>? tcpFlagsOutOf,
    List<String>? tcpFlagsSet,
    Object? gateway = _copyUnset,
    Object? schedule = _copyUnset,
    Object? dnpipe = _copyUnset,
    Object? pdnpipe = _copyUnset,
    Object? defaultQueue = _copyUnset,
    Object? ackQueue = _copyUnset,
    bool? floating,
    bool? quick,
    String? direction,
    Object? placement = _copyUnset,
  }) {
    return FirewallRule(
      id: id ?? this.id,
      section: section ?? this.section,
      type: type ?? this.type,
      interface: interface ?? '',
      interfaces: interfaces ??
          (interface == null ? this.interfaces : _normalizeInterfaces(null, interface)),
      ipProtocol: ipProtocol ?? this.ipProtocol,
      protocol:
          identical(protocol, _copyUnset) ? _protocol : protocol as String?,
      icmpTypes: icmpTypes ?? this.icmpTypes,
      sourceType: sourceType ?? this.sourceType,
      sourceNetwork: sourceNetwork ?? this.sourceNetwork,
      sourceInverted: sourceInverted ?? this.sourceInverted,
      sourcePort: identical(sourcePort, _copyUnset)
          ? this.sourcePort
          : sourcePort as String?,
      destinationType: destinationType ?? this.destinationType,
      destinationNetwork: destinationNetwork ?? this.destinationNetwork,
      destinationInverted: destinationInverted ?? this.destinationInverted,
      destinationPort: identical(destinationPort, _copyUnset)
          ? this.destinationPort
          : destinationPort as String?,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      log: log ?? this.log,
      tag: tag ?? this.tag,
      stateType: stateType ?? this.stateType,
      tcpFlagsAny: tcpFlagsAny ?? this.tcpFlagsAny,
      tcpFlagsOutOf: tcpFlagsOutOf ?? this.tcpFlagsOutOf,
      tcpFlagsSet: tcpFlagsSet ?? this.tcpFlagsSet,
      gateway: identical(gateway, _copyUnset) ? this.gateway : gateway as String?,
      schedule:
          identical(schedule, _copyUnset) ? this.schedule : schedule as String?,
      dnpipe: identical(dnpipe, _copyUnset) ? this.dnpipe : dnpipe as String?,
      pdnpipe:
          identical(pdnpipe, _copyUnset) ? this.pdnpipe : pdnpipe as String?,
      defaultQueue: identical(defaultQueue, _copyUnset)
          ? this.defaultQueue
          : defaultQueue as String?,
      ackQueue:
          identical(ackQueue, _copyUnset) ? this.ackQueue : ackQueue as String?,
      floating: floating ?? this.floating,
      quick: quick ?? this.quick,
      direction: direction ?? this.direction,
      placement: identical(placement, _copyUnset)
          ? this.placement
          : placement as int?,
      tracker: tracker,
      associatedRuleId: associatedRuleId,
      createdTime: createdTime,
      createdBy: createdBy,
      updatedTime: updatedTime,
      updatedBy: updatedBy,
    );
  }
}

List<String> _normalizeInterfaces(List<String>? interfaces, String interface) {
  final values = interfaces ?? interface.split(',');
  final result = <String>[];
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty && !result.contains(normalized)) result.add(normalized);
  }
  return result.isEmpty ? const ['wan'] : result;
}

(String value, bool inverted) _parseAddress(dynamic raw) {
  var value = raw?.toString().trim() ?? 'any';
  final inverted = value.startsWith('!');
  if (inverted) value = value.substring(1).trim();
  if (value.isEmpty || value == '*') value = 'any';
  return (value: value, inverted: inverted);
}

String _apiAddress(String value, bool inverted) {
  final normalized = _normalizeAddress(value);
  return inverted ? '!$normalized' : normalized;
}

String _normalizeAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '*') return 'any';
  return trimmed;
}

String? _normalizeProtocol(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty || normalized == 'any') {
    return null;
  }
  return normalized;
}

String? _normalizePortSpec(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _portSpecFromNumbers(int? from, int? to) {
  if (from == null && to == null) return null;
  final start = from ?? to;
  final end = to ?? from;
  if (start == null) return null;
  return end == null || end == start ? '$start' : '$start:$end';
}

(int?, int?) _numericPortRange(String? value) {
  if (value == null || value.isEmpty) return (null, null);
  final parts = value.split(RegExp('[:-]'));
  if (parts.length == 1) {
    final port = int.tryParse(parts.first);
    return (port, port);
  }
  return (int.tryParse(parts.first), int.tryParse(parts.last));
}

String _displayPort(String? value) {
  if (value == null) return '';
  return value.replaceFirst(':', '-');
}

bool _looksIpv6(String value) {
  final trimmed = value.toLowerCase();
  return trimmed.contains(':') && trimmed != 'any' && trimmed != '*';
}

List<String> _stringList(dynamic value, {List<String> fallback = const []}) {
  if (value == null) return List.unmodifiable(fallback);
  final values = value is List ? value : value.toString().split(',');
  final result = values
      .map((item) => item?.toString().trim().toLowerCase() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return result.isEmpty ? List.unmodifiable(fallback) : List.unmodifiable(result);
}

String _lower(dynamic value, {required String fallback}) {
  final text = value?.toString().trim().toLowerCase();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

int? _int(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}
