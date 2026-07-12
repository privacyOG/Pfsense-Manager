import 'dart:io';

import '../models/firewall_nat.dart';

const natIpProtocols = {'inet', 'inet6', 'inet46'};
const natPortProtocols = {'tcp', 'udp', 'tcp/udp'};
const natProtocols = {
  'any',
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
};
const outboundPoolOptions = {
  'round-robin',
  'round-robin sticky-address',
  'random',
  'random sticky-address',
  'source-hash',
  'bitmask',
};

class NatValidationException implements Exception {
  const NatValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

void validatePortForward(NatPortForward rule) {
  _required(rule.interface, 'Interface');
  _choice(rule.ipProtocol, natIpProtocols, 'IP protocol');
  _choice(rule.protocol, natProtocols, 'Protocol');
  _required(rule.source, 'Source');
  _required(rule.destination, 'Destination');
  _required(rule.target, 'Target');
  _validateAddressFamily(rule.target, rule.ipProtocol, 'Target');

  if (natPortProtocols.contains(rule.protocol)) {
    _validatePort(rule.sourcePort, 'Source port', allowEmpty: true);
    _validatePort(rule.destinationPort, 'Destination port', allowEmpty: true);
    _validatePort(rule.localPort, 'Local port', allowEmpty: false, allowRange: false);
  }

  final reflection = rule.reflection;
  if (reflection != null &&
      !const {'enable', 'disable', 'purenat'}.contains(reflection)) {
    throw const NatValidationException('NAT reflection mode is invalid.');
  }

  final associated = rule.associatedRuleId.trim();
  if (associated.isNotEmpty &&
      associated != 'new' &&
      associated != 'pass' &&
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(associated)) {
    throw const NatValidationException(
      'Associated firewall rule ID contains unsupported characters.',
    );
  }
}

void validateOneToOneMapping(NatOneToOneMapping mapping) {
  _required(mapping.interface, 'Interface');
  _choice(mapping.ipProtocol, const {'inet', 'inet6'}, 'IP protocol');
  _required(mapping.external, 'External address');
  _required(mapping.source, 'Source');
  _required(mapping.destination, 'Destination');
  _validateAddressFamily(mapping.external, mapping.ipProtocol, 'External address');
  _validateAddressFamily(mapping.source, mapping.ipProtocol, 'Source');
  _validateAddressFamily(mapping.destination, mapping.ipProtocol, 'Destination');

  final reflection = mapping.reflection;
  if (reflection != null && !const {'enable', 'disable'}.contains(reflection)) {
    throw const NatValidationException('NAT reflection mode is invalid.');
  }
}

void validateOutboundMapping(NatOutboundMapping mapping) {
  _required(mapping.interface, 'Interface');
  final protocol = mapping.protocol;
  if (protocol != null) _choice(protocol, natProtocols.difference({'any'}), 'Protocol');
  _required(mapping.source, 'Source network');
  _required(mapping.destination, 'Destination network');
  _validatePort(mapping.sourcePort, 'Source port', allowEmpty: true);
  _validatePort(mapping.destinationPort, 'Destination port', allowEmpty: true);

  if (mapping.noNat) return;

  _required(mapping.target, 'Translation target');
  final subnet = mapping.targetSubnet;
  if (subnet != null && (subnet < 1 || subnet > 128)) {
    throw const NatValidationException(
      'Target subnet must be between 1 and 128.',
    );
  }
  final targetAddress = InternetAddress.tryParse(mapping.target?.trim() ?? '');
  if (targetAddress?.type == InternetAddressType.IPv4 &&
      subnet != null &&
      subnet > 32) {
    throw const NatValidationException(
      'Target subnet must be 32 or less for an IPv4 target.',
    );
  }

  if (!mapping.staticNatPort) {
    _validatePort(mapping.natPort, 'NAT port', allowEmpty: true);
  }

  final pool = mapping.poolOptions;
  if (pool != null && !outboundPoolOptions.contains(pool)) {
    throw const NatValidationException('Pool option is invalid.');
  }
  if (pool == 'source-hash') {
    final key = mapping.sourceHashKey?.trim() ?? '';
    if (!RegExp(r'^0x[0-9A-Fa-f]{32}$').hasMatch(key)) {
      throw const NatValidationException(
        'Source hash key must be 0x followed by 32 hexadecimal characters.',
      );
    }
  }
}

void validateOutboundMode(OutboundNatMode mode) {
  if (!OutboundNatMode.values.contains(mode)) {
    throw const NatValidationException('Outbound NAT mode is invalid.');
  }
}

void _required(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    throw NatValidationException('$label is required.');
  }
}

void _choice(String value, Set<String> choices, String label) {
  if (!choices.contains(value)) {
    throw NatValidationException('$label is invalid.');
  }
}

void _validatePort(
  String? value,
  String label, {
  required bool allowEmpty,
  bool allowRange = true,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    if (allowEmpty) return;
    throw NatValidationException('$label is required.');
  }
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text)) return;

  final normalized = text.replaceAll(':', '-');
  final parts = normalized.split('-');
  if (parts.length > 2 || (!allowRange && parts.length != 1)) {
    throw NatValidationException('$label must be one port or a valid alias.');
  }
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((number) => number == null || number < 1 || number > 65535)) {
    throw NatValidationException('$label must be between 1 and 65535.');
  }
  if (numbers.length == 2 && numbers[0]! > numbers[1]!) {
    throw NatValidationException('$label range must start before it ends.');
  }
}

void _validateAddressFamily(String? value, String ipProtocol, String label) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty || raw == 'any') return;
  final candidate = raw.startsWith('!') ? raw.substring(1) : raw;
  final addressPart = candidate.split('/').first;
  final address = InternetAddress.tryParse(addressPart);
  if (address == null) return;

  if (ipProtocol == 'inet' && address.type == InternetAddressType.IPv6) {
    throw NatValidationException('$label must use IPv4 for this rule.');
  }
  if (ipProtocol == 'inet6' && address.type == InternetAddressType.IPv4) {
    throw NatValidationException('$label must use IPv6 for this rule.');
  }
}
