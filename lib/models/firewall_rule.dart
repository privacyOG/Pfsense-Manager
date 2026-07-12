import 'pfrest_capabilities.dart';
import '../utils/firewall_port_validation.dart';

/// Complete writable pfREST firewall-rule representation.
///
/// The original basic constructor parameters remain supported while richer
/// fields preserve floating, policy-routing, scheduling and shaping settings.
class FirewallRule {
  static const Object _unset = Object();

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
          _normaliseInterfaces(interfaces, interface),
        ),
        _protocol = _normaliseProtocol(protocol),
        sourcePort = _normalisePort(
          sourcePort ?? _portFromNumbers(sourcePortFrom, sourcePortTo),
        ),
        destinationPort = _normalisePort(
          destinationPort ??
              _portFromNumbers(destinationPortFrom, destinationPortTo),
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

  /// Optional common control parameter used to insert or move a rule.
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
      type: _lower(json['type'], 'pass'),
      interfaces: _strings(json['interface']),
      ipProtocol: _lower(json['ipprotocol'], 'inet'),
      protocol: json['protocol']?.toString(),
      icmpTypes: _strings(json['icmptype'], fallback: const ['any']),
      sourceType: json['source_type']?.toString() ?? 'network',
      sourceNetwork: source.value,
      sourceInverted: source.inverted,
      sourcePort: json['source_port']?.toString(),
      destinationType: json['destination_type']?.toString() ?? 'network',
      destinationNetwork: destination.value,
      destinationInverted: destination.inverted,
      destinationPort: json['destination_port']?.toString() ??
          _portFromNumbers(
            _integer(json['dst_port_from']),
            _integer(json['dst_port_to']),
          ),
      description: (json['descr'] ?? json['description'])?.toString() ?? '',
      enabled: !_boolean(json['disabled']),
      log: _boolean(json['log']),
      tag: json['tag']?.toString() ?? '',
      stateType: json['statetype']?.toString() ?? 'keep state',
      tcpFlagsAny: _boolean(json['tcp_flags_any'] ?? json['tcpflags_any']),
      tcpFlagsOutOf:
          _strings(json['tcp_flags_out_of'] ?? json['tcpflags2']),
      tcpFlagsSet: _strings(json['tcp_flags_set'] ?? json['tcpflags1']),
      gateway: _text(json['gateway']),
      schedule: _text(json['sched'] ?? json['schedule']),
      dnpipe: _text(json['dnpipe']),
      pdnpipe: _text(json['pdnpipe']),
      defaultQueue: _text(json['defaultqueue']),
      ackQueue: _text(json['ackqueue']),
      floating: _boolean(json['floating']),
      quick: _boolean(json['quick']),
      direction: json['direction']?.toString() ?? 'any',
      placement: _integer(json['placement']),
      tracker: _text(json['tracker']),
      associatedRuleId:
          _text(json['associated_rule_id'] ?? json['associated-rule-id']),
      createdTime: json['created_time']?.toString() ??
          created?['time']?.toString() ??
          created?['utc']?.toString() ??
          '',
      createdBy: json['created_by']?.toString() ??
          created?['username']?.toString() ??
          '',
      updatedTime: json['updated_time']?.toString() ??
          updated?['time']?.toString() ??
          updated?['utc']?.toString() ??
          '',
      updatedBy: json['updated_by']?.toString() ??
          updated?['username']?.toString() ??
          '',
    );
  }

  Map<String, dynamic> toJson() => toCreatePayload();

  Map<String, dynamic> toCreatePayload({
    PfRestOperationCapability? operation,
  }) {
    return _payload(
      operation: operation,
      includeNulls: false,
      includeFloating: true,
    );
  }

  Map<String, dynamic> toUpdatePayload({
    PfRestOperationCapability? operation,
  }) {
    return _payload(
      operation: operation,
      includeNulls: true,
      includeFloating: false,
    );
  }

  Map<String, dynamic> _payload({
    required PfRestOperationCapability? operation,
    required bool includeNulls,
    required bool includeFloating,
  }) {
    final supported = operation?.requestFields.values
        .where((field) => field.location == 'body')
        .map((field) => field.name)
        .toSet();
    bool allows(String name) => supported == null || supported.contains(name);

    final result = <String, dynamic>{};
    void put(String name, Object? value, {bool nullable = false}) {
      if (!allows(name)) return;
      if (value != null || !nullable || includeNulls) result[name] = value;
    }

    put('type', type.trim().toLowerCase());
    put('interface', interfaces);
    put('ipprotocol', _resolvedIpProtocol());
    put('protocol', _protocol, nullable: true);

    if (_protocol == 'icmp' && _resolvedIpProtocol() == 'inet') {
      put('icmptype', icmpTypes.isEmpty ? const ['any'] : icmpTypes);
    } else if (includeNulls) {
      put('icmptype', null, nullable: true);
    }

    put('source', _apiAddress(sourceNetwork, sourceInverted));
    put(
      'source_port',
      firewallProtocolSupportsPorts(_protocol) ? sourcePort : null,
      nullable: true,
    );
    put('destination', _apiAddress(destinationNetwork, destinationInverted));
    put(
      'destination_port',
      firewallProtocolSupportsPorts(_protocol) ? destinationPort : null,
      nullable: true,
    );
    put('descr', description.trim());
    put('disabled', !enabled);
    put('log', log);
    put('tag', tag.trim());
    put('statetype', stateType.trim().toLowerCase());

    if (_protocol == 'tcp') {
      put('tcp_flags_any', tcpFlagsAny);
      put(
        'tcp_flags_out_of',
        tcpFlagsAny ? null : tcpFlagsOutOf,
        nullable: true,
      );
      put(
        'tcp_flags_set',
        tcpFlagsAny ? null : tcpFlagsSet,
        nullable: true,
      );
    } else if (includeNulls) {
      put('tcp_flags_any', false);
      put('tcp_flags_out_of', null, nullable: true);
      put('tcp_flags_set', null, nullable: true);
    }

    put('gateway', _text(gateway), nullable: true);
    put('sched', _text(schedule), nullable: true);
    put('dnpipe', _text(dnpipe), nullable: true);
    put('pdnpipe', _text(pdnpipe), nullable: true);
    put('defaultqueue', _text(defaultQueue), nullable: true);
    put('ackqueue', _text(ackQueue), nullable: true);

    if (includeFloating) put('floating', floating);
    if (floating) {
      put('quick', quick);
      put('direction', direction.trim().toLowerCase());
    } else if (includeNulls) {
      put('quick', false);
      put('direction', 'any');
    }

    if (placement != null &&
        (operation == null || operation.field('placement') != null)) {
      result['placement'] = placement;
    }
    return result;
  }

  String get interface => interfaces.join(', ');
  String get protocol => _protocol ?? 'any';
  String? get apiProtocol => _protocol;
  String get protocolLabel => protocol.toUpperCase();
  int? get sourcePortFrom => _numericPorts(sourcePort).$1;
  int? get sourcePortTo => _numericPorts(sourcePort).$2;
  int? get destinationPortFrom => _numericPorts(destinationPort).$1;
  int? get destinationPortTo => _numericPorts(destinationPort).$2;
  String get sourcePortRange => _displayPort(sourcePort);
  String get portRange => _displayPort(destinationPort);

  String get typeIcon => switch (type.toLowerCase()) {
        'pass' => 'PASS',
        'block' => 'BLOCK',
        'reject' => 'REJECT',
        _ => '?',
      };

  String _resolvedIpProtocol() {
    final value = ipProtocol.trim().toLowerCase();
    if (const {'inet', 'inet6', 'inet46'}.contains(value)) return value;
    return _looksIpv6(sourceNetwork) || _looksIpv6(destinationNetwork)
        ? 'inet6'
        : 'inet';
  }

  FirewallRule copyWith({
    String? id,
    String? section,
    String? type,
    String? interface,
    List<String>? interfaces,
    String? ipProtocol,
    Object? protocol = _unset,
    List<String>? icmpTypes,
    String? sourceType,
    String? sourceNetwork,
    bool? sourceInverted,
    Object? sourcePort = _unset,
    String? destinationType,
    String? destinationNetwork,
    bool? destinationInverted,
    Object? destinationPort = _unset,
    String? description,
    bool? enabled,
    bool? log,
    String? tag,
    String? stateType,
    bool? tcpFlagsAny,
    List<String>? tcpFlagsOutOf,
    List<String>? tcpFlagsSet,
    Object? gateway = _unset,
    Object? schedule = _unset,
    Object? dnpipe = _unset,
    Object? pdnpipe = _unset,
    Object? defaultQueue = _unset,
    Object? ackQueue = _unset,
    bool? floating,
    bool? quick,
    String? direction,
    Object? placement = _unset,
  }) {
    return FirewallRule(
      id: id ?? this.id,
      section: section ?? this.section,
      type: type ?? this.type,
      interface: interface ?? '',
      interfaces: interfaces ??
          (interface == null
              ? this.interfaces
              : _normaliseInterfaces(null, interface)),
      ipProtocol: ipProtocol ?? this.ipProtocol,
      protocol: identical(protocol, _unset) ? _protocol : protocol as String?,
      icmpTypes: icmpTypes ?? this.icmpTypes,
      sourceType: sourceType ?? this.sourceType,
      sourceNetwork: sourceNetwork ?? this.sourceNetwork,
      sourceInverted: sourceInverted ?? this.sourceInverted,
      sourcePort:
          identical(sourcePort, _unset) ? this.sourcePort : sourcePort as String?,
      destinationType: destinationType ?? this.destinationType,
      destinationNetwork: destinationNetwork ?? this.destinationNetwork,
      destinationInverted: destinationInverted ?? this.destinationInverted,
      destinationPort: identical(destinationPort, _unset)
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
      gateway: identical(gateway, _unset) ? this.gateway : gateway as String?,
      schedule:
          identical(schedule, _unset) ? this.schedule : schedule as String?,
      dnpipe: identical(dnpipe, _unset) ? this.dnpipe : dnpipe as String?,
      pdnpipe: identical(pdnpipe, _unset) ? this.pdnpipe : pdnpipe as String?,
      defaultQueue: identical(defaultQueue, _unset)
          ? this.defaultQueue
          : defaultQueue as String?,
      ackQueue:
          identical(ackQueue, _unset) ? this.ackQueue : ackQueue as String?,
      floating: floating ?? this.floating,
      quick: quick ?? this.quick,
      direction: direction ?? this.direction,
      placement:
          identical(placement, _unset) ? this.placement : placement as int?,
      tracker: tracker,
      associatedRuleId: associatedRuleId,
      createdTime: createdTime,
      createdBy: createdBy,
      updatedTime: updatedTime,
      updatedBy: updatedBy,
    );
  }
}

List<String> _normaliseInterfaces(List<String>? values, String fallback) {
  final source = values ?? fallback.split(',');
  final result = <String>[];
  for (final value in source) {
    final item = value.trim();
    if (item.isNotEmpty && !result.contains(item)) result.add(item);
  }
  return result.isEmpty ? const ['wan'] : result;
}

({String value, bool inverted}) _parseAddress(dynamic raw) {
  var value = raw?.toString().trim() ?? 'any';
  final inverted = value.startsWith('!');
  if (inverted) value = value.substring(1).trim();
  if (value.isEmpty || value == '*') value = 'any';
  return (value: value, inverted: inverted);
}

String _apiAddress(String value, bool inverted) {
  final trimmed = value.trim();
  final normalised = trimmed.isEmpty || trimmed == '*' ? 'any' : trimmed;
  return inverted ? '!$normalised' : normalised;
}

String? _normaliseProtocol(String? value) {
  final text = value?.trim().toLowerCase();
  return text == null || text.isEmpty || text == 'any' ? null : text;
}

String? _normalisePort(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _portFromNumbers(int? from, int? to) {
  final start = from ?? to;
  final end = to ?? from;
  if (start == null) return null;
  return end == null || end == start ? '$start' : '$start:$end';
}

(int?, int?) _numericPorts(String? value) {
  if (value == null || value.isEmpty) return (null, null);
  final parts = value.split(RegExp('[:-]'));
  if (parts.length == 1) {
    final port = int.tryParse(parts.first);
    return (port, port);
  }
  return (int.tryParse(parts.first), int.tryParse(parts.last));
}

String _displayPort(String? value) => value?.replaceFirst(':', '-') ?? '';

bool _looksIpv6(String value) {
  final text = value.toLowerCase();
  return text.contains(':') && text != 'any' && text != '*';
}

List<String> _strings(dynamic value, {List<String> fallback = const []}) {
  if (value == null) return List.unmodifiable(fallback);
  final source = value is List ? value : value.toString().split(',');
  final result = source
      .map((item) => item?.toString().trim().toLowerCase() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return result.isEmpty ? List.unmodifiable(fallback) : List.unmodifiable(result);
}

String _lower(dynamic value, String fallback) {
  final text = value?.toString().trim().toLowerCase();
  return text == null || text.isEmpty ? fallback : text;
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text.toLowerCase() == 'null'
      ? null
      : text;
}

bool _boolean(dynamic value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes', 'on'}
      .contains(value?.toString().trim().toLowerCase());
}

int? _integer(dynamic value) {
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
