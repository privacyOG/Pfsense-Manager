import '../models/firewall_rule.dart';
import '../models/pfrest_capabilities.dart';
import 'firewall_port_validation.dart';

class FirewallRuleValidationResult {
  const FirewallRuleValidationResult({
    this.fieldErrors = const {},
    this.generalErrors = const [],
  });

  final Map<String, String> fieldErrors;
  final List<String> generalErrors;

  bool get isValid => fieldErrors.isEmpty && generalErrors.isEmpty;
  String? errorFor(String field) => fieldErrors[field];
  String? get summary => generalErrors.isEmpty ? null : generalErrors.join('\n');
}

const firewallRuleProtocols = <String>[
  'tcp',
  'udp',
  'tcp/udp',
  'icmp',
  'esp',
  'ah',
  'gre',
  'ipv6',
  'igmp',
  'pim',
  'ospf',
  'carp',
  'pfsync',
];

const firewallRuleStateTypes = <String>[
  'keep state',
  'sloppy state',
  'synproxy state',
  'none',
];

const firewallRuleTcpFlags = <String>[
  'fin',
  'syn',
  'rst',
  'psh',
  'ack',
  'urg',
  'ece',
  'cwr',
];

FirewallRuleValidationResult validateFirewallRule(
  FirewallRule rule, {
  PfRestOperationCapability? operation,
}) {
  final fieldErrors = <String, String>{};
  final generalErrors = <String>[];

  void error(String field, String message) {
    fieldErrors.putIfAbsent(field, () => message);
  }

  final types = _allowed(operation, 'type', const ['pass', 'block', 'reject']);
  if (!types.contains(rule.type.toLowerCase())) {
    error('type', 'Select a rule action supported by this pfREST installation.');
  }

  if (rule.interfaces.isEmpty) {
    error('interface', 'Select at least one interface.');
  } else if (!rule.floating && rule.interfaces.length > 1) {
    error(
      'interface',
      'Multiple interfaces require a floating firewall rule.',
    );
  }

  final ipProtocols =
      _allowed(operation, 'ipprotocol', const ['inet', 'inet6', 'inet46']);
  if (!ipProtocols.contains(rule.ipProtocol.toLowerCase())) {
    error('ipprotocol', 'Select a supported IP version.');
  }

  final protocol = rule.apiProtocol;
  final protocols = _allowed(operation, 'protocol', firewallRuleProtocols);
  if (protocol != null && !protocols.contains(protocol)) {
    error('protocol', 'Select a protocol supported by this pfREST installation.');
  }

  _validateText(rule.description, operation?.field('descr'), 'descr', error);
  _validateText(rule.tag, operation?.field('tag'), 'tag', error);

  _validateAddress(
    field: 'source',
    value: rule.sourceNetwork,
    inverted: rule.sourceInverted,
    error: error,
  );
  _validateAddress(
    field: 'destination',
    value: rule.destinationNetwork,
    inverted: rule.destinationInverted,
    error: error,
  );
  _validateAddressFamily(rule, error);

  final supportsPorts = firewallProtocolSupportsPorts(protocol);
  if (!supportsPorts && rule.sourcePort != null) {
    error('source_port', 'Source ports apply only to TCP and UDP rules.');
  } else {
    _validatePortSpec(rule.sourcePort, 'source_port', error);
  }
  if (!supportsPorts && rule.destinationPort != null) {
    error(
      'destination_port',
      'Destination ports apply only to TCP and UDP rules.',
    );
  } else {
    _validatePortSpec(rule.destinationPort, 'destination_port', error);
  }

  if (rule.icmpTypes.isNotEmpty &&
      !(protocol == 'icmp' && rule.ipProtocol == 'inet') &&
      rule.icmpTypes.any((value) => value != 'any')) {
    error(
      'icmptype',
      'ICMP types require an IPv4 ICMP rule.',
    );
  }
  final allowedIcmpTypes = _allowed(operation, 'icmptype', const []);
  if (allowedIcmpTypes.isNotEmpty &&
      rule.icmpTypes.any((type) => !allowedIcmpTypes.contains(type))) {
    error('icmptype', 'One or more ICMP types are not supported.');
  }

  final stateTypes = _allowed(operation, 'statetype', firewallRuleStateTypes);
  if (!stateTypes.contains(rule.stateType)) {
    error('statetype', 'Select a supported state type.');
  }
  if (rule.stateType == 'synproxy state' && protocol != 'tcp') {
    error('statetype', 'SYN proxy state requires TCP.');
  }
  if (rule.stateType == 'synproxy state' && _hasText(rule.gateway)) {
    error('gateway', 'A gateway cannot be used with SYN proxy state.');
  }

  final hasTcpFlags = rule.tcpFlagsAny ||
      rule.tcpFlagsOutOf.isNotEmpty ||
      rule.tcpFlagsSet.isNotEmpty;
  if (hasTcpFlags && protocol != 'tcp') {
    error('tcp_flags', 'TCP flags apply only to TCP rules.');
  }
  if (!rule.tcpFlagsAny) {
    final outOf = rule.tcpFlagsOutOf.toSet();
    final unsupported = <String>{
      ...rule.tcpFlagsOutOf.where((flag) => !firewallRuleTcpFlags.contains(flag)),
      ...rule.tcpFlagsSet.where((flag) => !firewallRuleTcpFlags.contains(flag)),
    };
    if (unsupported.isNotEmpty) {
      error('tcp_flags', 'One or more TCP flags are not supported.');
    }
    if (rule.tcpFlagsSet.any((flag) => !outOf.contains(flag))) {
      error(
        'tcp_flags_set',
        'Every required TCP flag must also be selected in “out of”.',
      );
    }
  }

  if (!rule.floating) {
    if (rule.quick) error('quick', 'Quick mode applies only to floating rules.');
    if (rule.direction != 'any') {
      error('direction', 'Direction applies only to floating rules.');
    }
  } else {
    final directions = _allowed(operation, 'direction', const ['any', 'in', 'out']);
    if (!directions.contains(rule.direction)) {
      error('direction', 'Select a supported floating-rule direction.');
    }
  }

  if (_hasText(rule.pdnpipe) && !_hasText(rule.dnpipe)) {
    error('pdnpipe', 'An outbound limiter requires an inbound limiter.');
  }
  if (_hasText(rule.pdnpipe) && rule.pdnpipe == rule.dnpipe) {
    error('pdnpipe', 'Inbound and outbound limiters must be different.');
  }
  if (_hasText(rule.ackQueue) && !_hasText(rule.defaultQueue)) {
    error('ackqueue', 'An ACK queue requires a default queue.');
  }
  if (_hasText(rule.ackQueue) && rule.ackQueue == rule.defaultQueue) {
    error('ackqueue', 'Default and ACK queues must be different.');
  }

  final placement = rule.placement;
  final placementConstraint = operation?.field('placement');
  if (placement != null) {
    if (placement < 0) {
      error('placement', 'Placement must be zero or greater.');
    } else if (placementConstraint != null &&
        !placementConstraint.permitsNumber(placement)) {
      error('placement', 'Placement is outside the installed schema range.');
    }
  }

  if (operation != null) {
    for (final field in operation.requestFields.values) {
      if (field.location != 'body' || !field.required) continue;
      final value = _ruleFieldValue(rule, field.name);
      if (_isMissing(value)) {
        error(field.name, '${_label(field.name)} is required by this schema.');
      }
    }
  }

  if (fieldErrors.isNotEmpty) {
    generalErrors.add('Review the highlighted firewall rule fields.');
  }
  return FirewallRuleValidationResult(
    fieldErrors: Map.unmodifiable(fieldErrors),
    generalErrors: List.unmodifiable(generalErrors),
  );
}

List<String> firewallRuleAllowedValues(
  PfRestOperationCapability? operation,
  String field,
  List<String> fallback,
) {
  return _allowed(operation, field, fallback);
}

void _validateAddress({
  required String field,
  required String value,
  required bool inverted,
  required void Function(String, String) error,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    error(field, '${_label(field)} is required.');
  }
  if (inverted && (normalized == 'any' || normalized == '*')) {
    error(field, '${_label(field)} cannot invert “any”.');
  }
}

void _validateAddressFamily(
  FirewallRule rule,
  void Function(String, String) error,
) {
  for (final entry in {
    'source': rule.sourceNetwork,
    'destination': rule.destinationNetwork,
  }.entries) {
    final value = entry.value.trim();
    if (!_isLiteralAddress(value)) continue;
    final ipv6 = value.contains(':');
    if (rule.ipProtocol == 'inet' && ipv6) {
      error(entry.key, '${_label(entry.key)} is IPv6 but the rule is IPv4 only.');
    }
    if (rule.ipProtocol == 'inet6' && !ipv6) {
      error(entry.key, '${_label(entry.key)} is IPv4 but the rule is IPv6 only.');
    }
  }
}

bool _isLiteralAddress(String value) {
  final normalized = value.startsWith('!') ? value.substring(1) : value;
  if (normalized == 'any' ||
      normalized == '*' ||
      normalized == '(self)' ||
      normalized == 'l2tp' ||
      normalized == 'pppoe') {
    return false;
  }
  if (normalized.contains(':')) return true;
  return RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}(?:/\d{1,2})?$')
      .hasMatch(normalized);
}

void _validatePortSpec(
  String? value,
  String field,
  void Function(String, String) error,
) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return;
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text)) return;

  final parts = text.split(RegExp('[:-]'));
  if (parts.length > 2 || parts.any((part) => int.tryParse(part) == null)) {
    error(field, 'Use a port, an ascending range, or a port alias.');
    return;
  }
  final from = int.parse(parts.first);
  final to = parts.length == 1 ? from : int.parse(parts.last);
  if (from < 1 || from > 65535 || to < 1 || to > 65535) {
    error(field, 'Ports must be between 1 and 65535.');
  } else if (to < from) {
    error(field, 'The ending port must be greater than or equal to the start.');
  }
}

void _validateText(
  String value,
  PfRestFieldConstraint? constraint,
  String field,
  void Function(String, String) error,
) {
  if (constraint == null) return;
  if (constraint.minLength != null && value.length < constraint.minLength!) {
    error(field, '${_label(field)} is shorter than the installed schema allows.');
  }
  if (constraint.maxLength != null && value.length > constraint.maxLength!) {
    error(field, '${_label(field)} is longer than the installed schema allows.');
  }
  final pattern = constraint.pattern;
  if (pattern != null && pattern.isNotEmpty) {
    try {
      if (!RegExp(pattern).hasMatch(value)) {
        error(field, '${_label(field)} does not match the installed schema.');
      }
    } on FormatException {
      // A server-side regular expression may not use Dart syntax. The server
      // remains the final authority when the expression cannot be evaluated.
    }
  }
}

List<String> _allowed(
  PfRestOperationCapability? operation,
  String field,
  List<String> fallback,
) {
  final values = operation
      ?.field(field)
      ?.allowedValues
      .whereType<Object>()
      .map((value) => value.toString().trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  return values == null || values.isEmpty ? fallback : values;
}

dynamic _ruleFieldValue(FirewallRule rule, String field) => switch (field) {
      'type' => rule.type,
      'interface' => rule.interfaces,
      'ipprotocol' => rule.ipProtocol,
      'protocol' => rule.apiProtocol,
      'icmptype' => rule.icmpTypes,
      'source' => rule.sourceNetwork,
      'source_port' => rule.sourcePort,
      'destination' => rule.destinationNetwork,
      'destination_port' => rule.destinationPort,
      'descr' => rule.description,
      'disabled' => !rule.enabled,
      'log' => rule.log,
      'tag' => rule.tag,
      'statetype' => rule.stateType,
      'tcp_flags_any' => rule.tcpFlagsAny,
      'tcp_flags_out_of' => rule.tcpFlagsOutOf,
      'tcp_flags_set' => rule.tcpFlagsSet,
      'gateway' => rule.gateway,
      'sched' => rule.schedule,
      'dnpipe' => rule.dnpipe,
      'pdnpipe' => rule.pdnpipe,
      'defaultqueue' => rule.defaultQueue,
      'ackqueue' => rule.ackQueue,
      'floating' => rule.floating,
      'quick' => rule.quick,
      'direction' => rule.direction,
      'placement' => rule.placement,
      _ => true,
    };

bool _isMissing(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  return false;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _label(String field) => switch (field) {
      'ipprotocol' => 'IP version',
      'icmptype' => 'ICMP type',
      'source_port' => 'Source port',
      'destination_port' => 'Destination port',
      'descr' => 'Description',
      'statetype' => 'State type',
      'tcp_flags_set' => 'Required TCP flags',
      'pdnpipe' => 'Outbound limiter',
      'ackqueue' => 'ACK queue',
      _ => field
          .split('_')
          .map((part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
    };
