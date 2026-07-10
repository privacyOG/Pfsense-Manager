/// Firewall rule model from pfSense REST API.
class FirewallRule {
  static const Object _copyUnset = Object();

  final String? id;
  final String section;
  final String type; // pass, block, reject
  final String interface;
  final String ipProtocol;
  final String? _protocol;
  final String sourceType;
  final String sourceNetwork;
  final String destinationType;
  final String destinationNetwork;
  final int? destinationPortFrom;
  final int? destinationPortTo;
  final String description;
  final bool enabled;
  final String createdTime;

  FirewallRule({
    this.id,
    required this.section,
    required this.type,
    required this.interface,
    this.ipProtocol = 'inet',
    required String? protocol,
    required this.sourceType,
    required this.sourceNetwork,
    required this.destinationType,
    required this.destinationNetwork,
    this.destinationPortFrom,
    this.destinationPortTo,
    required this.description,
    required this.enabled,
    required this.createdTime,
  }) : _protocol = _normalizeProtocol(protocol);

  factory FirewallRule.fromJson(Map<String, dynamic> json) {
    final interfaces = json['interface'];
    final destinationPort = json['destination_port']?.toString();
    final destinationPorts = _parsePortRange(destinationPort);

    return FirewallRule(
      id: (json['id'] ?? json['uuid'])?.toString(),
      section: json['section'] as String? ?? '',
      type: (json['type'] as String?)?.toLowerCase() ?? 'pass',
      interface: interfaces is List
          ? interfaces.join(', ')
          : interfaces as String? ?? '',
      ipProtocol: (json['ipprotocol'] as String?)?.toLowerCase() ?? 'inet',
      protocol: json['protocol']?.toString(),
      sourceType: json['source_type'] as String? ?? 'network',
      sourceNetwork:
          json['source_network'] as String? ?? json['source'] as String? ?? '*',
      destinationType: json['destination_type'] as String? ?? 'network',
      destinationNetwork: json['destination_network'] as String? ??
          json['destination'] as String? ??
          '*',
      destinationPortFrom: json['dst_port_from'] != null
          ? int.tryParse(json['dst_port_from'].toString())
          : destinationPorts.$1,
      destinationPortTo: json['dst_port_to'] != null
          ? int.tryParse(json['dst_port_to'].toString())
          : destinationPorts.$2,
      description:
          json['description'] as String? ?? json['descr'] as String? ?? '',
      enabled: !(json['disabled'] as bool? ?? false),
      createdTime: json['created_time']?.toString() ??
          ((json['created'] is Map<String, dynamic>)
              ? json['created']['utc'] as String? ?? ''
              : ''),
    );
  }

  Map<String, dynamic> toJson() {
    final destinationPort = destinationPortFrom == null
        ? null
        : destinationPortFrom == destinationPortTo || destinationPortTo == null
            ? destinationPortFrom.toString()
            : '$destinationPortFrom:$destinationPortTo';
    final interfaces = interface
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    return {
      'type': type.toLowerCase(),
      'interface': interfaces,
      'ipprotocol': _resolveIpProtocol(),
      if (_protocol != null) 'protocol': _protocol,
      'source': _normalizeAddress(sourceNetwork),
      'destination': _normalizeAddress(destinationNetwork),
      if (destinationPort != null) 'destination_port': destinationPort,
      'descr': description,
      'disabled': !enabled,
    };
  }

  String get protocol => _protocol ?? 'any';

  String? get apiProtocol => _protocol;

  String get protocolLabel => protocol.toUpperCase();

  String get portRange {
    if (destinationPortFrom == null && destinationPortTo == null) return '';
    if (destinationPortFrom == destinationPortTo) {
      return '$destinationPortFrom';
    }
    return '$destinationPortFrom-$destinationPortTo';
  }

  String get typeIcon {
    switch (type.toLowerCase()) {
      case 'pass':
        return 'PASS';
      case 'block':
        return 'BLOCK';
      case 'reject':
        return 'REJECT';
      default:
        return '?';
    }
  }

  String _resolveIpProtocol() {
    final value = ipProtocol.trim().toLowerCase();
    if (value == 'inet' || value == 'inet6' || value == 'inet46') {
      return value;
    }
    final source = sourceNetwork.trim();
    final destination = destinationNetwork.trim();
    if (_looksIpv6(source) || _looksIpv6(destination)) return 'inet6';
    return 'inet';
  }

  static bool _looksIpv6(String value) {
    final trimmed = value.toLowerCase();
    return trimmed.contains(':') && trimmed != 'any' && trimmed != '*';
  }

  static (int?, int?) _parsePortRange(String? value) {
    if (value == null || value.isEmpty) return (null, null);
    final separator = value.contains(':') ? ':' : '-';
    final parts = value.split(separator);
    if (parts.length == 1) {
      final port = int.tryParse(parts.first);
      return (port, port);
    }
    return (int.tryParse(parts.first), int.tryParse(parts.last));
  }

  static String _normalizeAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '*') return 'any';
    return trimmed;
  }

  static String? _normalizeProtocol(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'any') {
      return null;
    }
    return normalized;
  }

  FirewallRule copyWith({
    String? id,
    String? section,
    String? type,
    String? interface,
    String? ipProtocol,
    Object? protocol = _copyUnset,
    String? sourceType,
    String? sourceNetwork,
    String? destinationType,
    String? destinationNetwork,
    int? destinationPortFrom,
    int? destinationPortTo,
    String? description,
    bool? enabled,
  }) {
    return FirewallRule(
      id: id ?? this.id,
      section: section ?? this.section,
      type: type ?? this.type,
      interface: interface ?? this.interface,
      ipProtocol: ipProtocol ?? this.ipProtocol,
      protocol:
          identical(protocol, _copyUnset) ? _protocol : protocol as String?,
      sourceType: sourceType ?? this.sourceType,
      sourceNetwork: sourceNetwork ?? this.sourceNetwork,
      destinationType: destinationType ?? this.destinationType,
      destinationNetwork: destinationNetwork ?? this.destinationNetwork,
      destinationPortFrom: destinationPortFrom ?? this.destinationPortFrom,
      destinationPortTo: destinationPortTo ?? this.destinationPortTo,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      createdTime: createdTime,
    );
  }
}
