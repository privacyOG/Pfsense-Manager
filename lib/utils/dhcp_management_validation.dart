import 'dart:io';

import '../models/dhcp_management.dart';
import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';

class DhcpValidationResult {
  const DhcpValidationResult(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String get summary => isValid ? 'Valid' : errors.values.first;
}

class DhcpValidationContext {
  const DhcpValidationContext({
    this.interfaces = const [],
    this.servers = const [],
    this.staticMappings = const [],
    this.addressPools = const [],
    this.relayEnabled = false,
    this.editing,
  });

  final List<ManagedInterfaceResource> interfaces;
  final List<ManagedDhcpResource> servers;
  final List<ManagedDhcpResource> staticMappings;
  final List<ManagedDhcpResource> addressPools;
  final bool relayEnabled;
  final ManagedDhcpResource? editing;
}

Map<String, dynamic> normaliseDhcpValues(
  DhcpResourceKind kind,
  Map<String, dynamic> values,
) {
  final result = <String, dynamic>{};
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) {
      result[entry.key] = value.trim();
    } else if (value is List) {
      result[entry.key] = value
          .map((item) => item is String ? item.trim() : item)
          .where((item) => item is! String || item.isNotEmpty)
          .toList(growable: false);
    } else {
      result[entry.key] = value;
    }
  }

  for (final key in const ['defaultleasetime', 'maxleasetime']) {
    final value = result[key];
    if (value is String && value.isNotEmpty) {
      result[key] = int.tryParse(value) ?? value;
    }
  }
  return result;
}

DhcpValidationResult validateDhcpResourceValues({
  required DhcpResourceKind kind,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  DhcpValidationContext context = const DhcpValidationContext(),
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);

  switch (kind) {
    case DhcpResourceKind.server:
      _validateServer(values, context, errors);
    case DhcpResourceKind.staticMapping:
      _validateStaticMapping(values, context, errors);
    case DhcpResourceKind.addressPool:
      _validateAddressPool(values, context, errors);
  }

  return DhcpValidationResult(Map.unmodifiable(errors));
}

DhcpValidationResult validateDhcpRelayValues({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  required List<ManagedDhcpResource> servers,
  required List<ManagedInterfaceResource> interfaces,
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);
  final enabled = _boolean(values['enable']);
  final selectedInterfaces = _stringList(values['interface']);
  final destinations = _stringList(values['server']);

  if (enabled && servers.any((server) => server.enabled)) {
    errors['enable'] =
        'Disable every DHCP server before enabling the DHCP relay.';
  }
  if (enabled && selectedInterfaces.isEmpty) {
    errors['interface'] = 'Select at least one downstream interface.';
  }
  if (enabled && destinations.isEmpty) {
    errors['server'] = 'Enter at least one upstream DHCP server.';
  }

  final knownInterfaces = <String>{
    for (final interface in interfaces) ...[
      interface.id?.toString().trim() ?? '',
      interface.interfaceName,
    ],
  }..remove('');
  for (final selected in selectedInterfaces) {
    if (knownInterfaces.isNotEmpty && !knownInterfaces.contains(selected)) {
      errors['interface'] = 'A selected relay interface is no longer available.';
      break;
    }
  }
  for (final destination in destinations) {
    if (!_isIpv4(destination)) {
      errors['server'] = 'Relay destinations must be valid IPv4 addresses.';
      break;
    }
  }

  return DhcpValidationResult(Map.unmodifiable(errors));
}

DhcpValidationResult validateDhcpBackendValue({
  required String backend,
  required PfRestOperationCapability operation,
}) {
  final errors = <String, String>{};
  final field = operation.field('dhcpbackend', location: 'body');
  if (field == null) {
    errors['dhcpbackend'] = 'Backend selection is not reported by this schema.';
  } else if (backend.trim().isEmpty) {
    errors['dhcpbackend'] = 'Select a DHCP backend.';
  } else if (field.allowedValues.isNotEmpty &&
      !field.allowedValues.map((value) => value.toString()).contains(backend)) {
    errors['dhcpbackend'] = 'The selected DHCP backend is not supported.';
  }
  return DhcpValidationResult(Map.unmodifiable(errors));
}

void _validateServer(
  Map<String, dynamic> values,
  DhcpValidationContext context,
  Map<String, String> errors,
) {
  final interfaceId = _text(values['id'] ?? values['interface']);
  if (interfaceId.isEmpty) {
    errors['id'] = 'Select an interface for this DHCP server.';
    return;
  }

  final interface = _interfaceForId(context.interfaces, interfaceId);
  final enabled = _boolean(values['enable']);
  if (enabled && context.relayEnabled) {
    errors['enable'] = 'Disable the DHCP relay before enabling a DHCP server.';
  }
  if (enabled && interface != null && interface.ipv4Mode != 'static') {
    errors['enable'] =
        'DHCP can only be enabled on an interface with static IPv4 addressing.';
  }

  final subnet = _subnetForInterface(interface);
  final range = _validateRange(
    values,
    subnet: subnet,
    required: false,
    errors: errors,
  );
  if (range != null) {
    for (final server in context.servers) {
      if (_sameResource(server, context.editing)) continue;
      final otherRange = _rangeForResource(server);
      if (otherRange != null && range.overlaps(otherRange)) {
        errors['range_from'] =
            'This range overlaps the DHCP range on ${server.displayName}.';
        break;
      }
    }
    for (final mapping in context.staticMappings) {
      if (mapping.parentId != interfaceId) continue;
      final ip = _ipv4ToInt(mapping.ipAddress);
      if (ip != null && range.containsValue(ip)) {
        errors['range_from'] =
            'This range includes the static mapping ${mapping.displayName}.';
        break;
      }
    }
    for (final pool in context.addressPools) {
      if (pool.parentId != interfaceId) continue;
      final otherRange = _rangeForResource(pool);
      if (otherRange != null && range.overlaps(otherRange)) {
        errors['range_from'] =
            'This range overlaps the additional pool ${pool.displayName}.';
        break;
      }
    }
  }

  _validateLeaseTimes(values, errors);
  _validateGateway(values, subnet, errors);
  _validateServerLists(values, errors);

  if (_boolean(values['nonak']) && _text(values['failover_peerip']).isNotEmpty) {
    errors['nonak'] = 'No NAK cannot be enabled with a failover peer.';
  }
  final failover = _text(values['failover_peerip']);
  if (failover.isNotEmpty &&
      !_isIpv4(failover) &&
      !_isIpv6(failover) &&
      !_isHostname(failover)) {
    errors['failover_peerip'] =
        'Enter a valid IP address or hostname for the failover peer.';
  }
}

void _validateStaticMapping(
  Map<String, dynamic> values,
  DhcpValidationContext context,
  Map<String, String> errors,
) {
  final parentId = _text(values['parent_id']);
  if (parentId.isEmpty) {
    errors['parent_id'] = 'Select the DHCP server interface.';
    return;
  }
  final parent = context.servers
      .where((server) => server.interfaceId == parentId)
      .firstOrNull;
  final interface = _interfaceForId(context.interfaces, parentId);
  final subnet = _subnetForInterface(interface);

  final mac = _text(values['mac']);
  if (!_isMac(mac)) {
    errors['mac'] = 'Enter a valid MAC address.';
  } else {
    for (final mapping in context.staticMappings) {
      if (_sameResource(mapping, context.editing)) continue;
      if (mapping.macAddress.toLowerCase() == mac.toLowerCase()) {
        errors['mac'] = 'This MAC address already has a static mapping.';
        break;
      }
    }
  }

  final ipText = _text(values['ipaddr']);
  if (ipText.isEmpty) {
    if (_boolean(parent?.raw['staticarp'])) {
      errors['ipaddr'] =
          'An IP address is required while Static ARP is enabled on this server.';
    }
  } else {
    final ip = _ipv4ToInt(ipText);
    if (ip == null) {
      errors['ipaddr'] = 'Enter a valid IPv4 address.';
    } else {
      if (subnet != null && !subnet.containsHost(ip)) {
        errors['ipaddr'] =
            'The static address must be a usable host in the interface subnet.';
      }
      final primary = parent == null ? null : _rangeForResource(parent);
      if (primary != null && primary.containsValue(ip)) {
        errors['ipaddr'] =
            'Static addresses cannot be inside the primary DHCP range.';
      }
      for (final pool in context.addressPools) {
        if (pool.parentId != parentId) continue;
        final range = _rangeForResource(pool);
        if (range != null && range.containsValue(ip)) {
          errors['ipaddr'] =
              'Static addresses cannot be inside an additional DHCP pool.';
          break;
        }
      }
      for (final mapping in context.staticMappings) {
        if (_sameResource(mapping, context.editing)) continue;
        if (mapping.ipAddress == ipText) {
          errors['ipaddr'] = 'This IP address is already statically mapped.';
          break;
        }
      }
    }
  }

  final hostname = _text(values['hostname']);
  if (hostname.isNotEmpty && !_isHostname(hostname)) {
    errors['hostname'] = 'Enter a valid hostname.';
  }
  _validateLeaseTimes(values, errors);
  _validateGateway(values, subnet, errors);
  _validateServerLists(values, errors, mapping: true);
}

void _validateAddressPool(
  Map<String, dynamic> values,
  DhcpValidationContext context,
  Map<String, String> errors,
) {
  final parentId = _text(values['parent_id']);
  if (parentId.isEmpty) {
    errors['parent_id'] = 'Select the DHCP server interface.';
    return;
  }
  final parent = context.servers
      .where((server) => server.interfaceId == parentId)
      .firstOrNull;
  final interface = _interfaceForId(context.interfaces, parentId);
  final subnet = _subnetForInterface(interface);
  final range = _validateRange(
    values,
    subnet: subnet,
    required: true,
    errors: errors,
  );
  if (range != null) {
    final primary = parent == null ? null : _rangeForResource(parent);
    if (primary != null && range.overlaps(primary)) {
      errors['range_from'] = 'This pool overlaps the primary DHCP range.';
    }
    for (final pool in context.addressPools) {
      if (_sameResource(pool, context.editing) || pool.parentId != parentId) {
        continue;
      }
      final otherRange = _rangeForResource(pool);
      if (otherRange != null && range.overlaps(otherRange)) {
        errors['range_from'] =
            'This pool overlaps the additional pool ${pool.displayName}.';
        break;
      }
    }
    for (final mapping in context.staticMappings) {
      if (mapping.parentId != parentId) continue;
      final ip = _ipv4ToInt(mapping.ipAddress);
      if (ip != null && range.containsValue(ip)) {
        errors['range_from'] =
            'This pool includes the static mapping ${mapping.displayName}.';
        break;
      }
    }
  }
  _validateLeaseTimes(values, errors);
  _validateGateway(values, subnet, errors);
  _validateServerLists(values, errors);
}

_Ipv4Range? _validateRange(
  Map<String, dynamic> values, {
  required _Ipv4Subnet? subnet,
  required bool required,
  required Map<String, String> errors,
}) {
  final fromText = _text(values['range_from']);
  final toText = _text(values['range_to']);
  if (fromText.isEmpty && toText.isEmpty && !required) return null;
  if (fromText.isEmpty || toText.isEmpty) {
    errors[fromText.isEmpty ? 'range_from' : 'range_to'] =
        'Enter both the start and end of the DHCP range.';
    return null;
  }
  final from = _ipv4ToInt(fromText);
  final to = _ipv4ToInt(toText);
  if (from == null) errors['range_from'] = 'Enter a valid IPv4 address.';
  if (to == null) errors['range_to'] = 'Enter a valid IPv4 address.';
  if (from == null || to == null) return null;
  if (from > to) {
    errors['range_from'] = 'The range start cannot be greater than the range end.';
    return null;
  }
  if (subnet != null) {
    if (!subnet.containsHost(from)) {
      errors['range_from'] =
          'The range start must be a usable host in the interface subnet.';
    }
    if (!subnet.containsHost(to)) {
      errors['range_to'] =
          'The range end must be a usable host in the interface subnet.';
    }
  }
  return _Ipv4Range(from, to);
}

void _validateLeaseTimes(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final defaultLease = _integer(values['defaultleasetime']);
  final maxLease = _integer(values['maxleasetime']);
  if (defaultLease != null && defaultLease < 60) {
    errors['defaultleasetime'] = 'Default lease time must be at least 60 seconds.';
  }
  if (maxLease != null && maxLease < 60) {
    errors['maxleasetime'] = 'Maximum lease time must be at least 60 seconds.';
  }
  if (defaultLease != null && maxLease != null && maxLease < defaultLease) {
    errors['maxleasetime'] =
        'Maximum lease time cannot be less than the default lease time.';
  }
}

void _validateGateway(
  Map<String, dynamic> values,
  _Ipv4Subnet? subnet,
  Map<String, String> errors,
) {
  final gateway = _text(values['gateway']);
  if (gateway.isEmpty || gateway == 'none') return;
  final address = _ipv4ToInt(gateway);
  if (address == null) {
    errors['gateway'] = 'Enter a valid IPv4 gateway or none.';
  } else if (subnet != null && !subnet.containsHost(address)) {
    errors['gateway'] = 'The gateway must be inside the interface subnet.';
  }
}

void _validateServerLists(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  bool mapping = false,
}) {
  _validateIpList(values, 'dnsserver', 4, errors);
  _validateIpList(values, 'winsserver', 2, errors);
  _validateIpList(values, 'ntpserver', mapping ? 3 : 4, errors,
      allowHostname: true);
  _validateMacList(values, 'mac_allow', errors);
  _validateMacList(values, 'mac_deny', errors);
  final domains = _stringList(values['domainsearchlist']);
  if (domains.any((value) => !_isHostname(value))) {
    errors['domainsearchlist'] =
        'Domain search entries must be valid host or domain names.';
  }
}

void _validateIpList(
  Map<String, dynamic> values,
  String name,
  int maximum,
  Map<String, String> errors, {
  bool allowHostname = false,
}) {
  final entries = _stringList(values[name]);
  if (entries.length > maximum) {
    errors[name] = 'Enter no more than $maximum values.';
    return;
  }
  for (final entry in entries) {
    if (!_isIpv4(entry) && !(allowHostname && _isHostname(entry))) {
      errors[name] = allowHostname
          ? 'Entries must be valid IPv4 addresses or hostnames.'
          : 'Entries must be valid IPv4 addresses.';
      return;
    }
  }
}

void _validateMacList(
  Map<String, dynamic> values,
  String name,
  Map<String, String> errors,
) {
  if (_stringList(values[name]).any((value) => !_isMac(value))) {
    errors[name] = 'Every entry must be a valid MAC address.';
  }
}

void _validateSchema(
  Map<String, dynamic> values,
  PfRestOperationCapability operation,
  Map<String, String> errors,
) {
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body') continue;
    final value = values[field.name];
    if (field.required && _isEmpty(value)) {
      errors[field.name] = '${_label(field.name)} is required.';
      continue;
    }
    if (_isEmpty(value)) continue;

    if ((field.type == 'integer' || field.type == 'number') &&
        field.name != 'id' &&
        field.name != 'parent_id') {
      final number = value is num ? value : num.tryParse(value.toString());
      if (number == null) {
        errors[field.name] = '${_label(field.name)} must be a number.';
      } else if (!field.permitsNumber(number)) {
        errors[field.name] = '${_label(field.name)} is outside the allowed range.';
      }
    }
    final text = value is String ? value : null;
    if (text != null) {
      if (field.minLength != null && text.length < field.minLength!) {
        errors[field.name] = '${_label(field.name)} is too short.';
      }
      if (field.maxLength != null && text.length > field.maxLength!) {
        errors[field.name] = '${_label(field.name)} is too long.';
      }
      if (field.pattern != null &&
          field.pattern!.isNotEmpty &&
          !RegExp(field.pattern!).hasMatch(text)) {
        errors[field.name] = '${_label(field.name)} has an invalid format.';
      }
    }
    if (field.allowedValues.isNotEmpty &&
        !field.allowedValues.map((value) => value?.toString()).contains(
              value.toString(),
            )) {
      errors[field.name] = '${_label(field.name)} is not supported.';
    }
  }
}

ManagedInterfaceResource? _interfaceForId(
  List<ManagedInterfaceResource> interfaces,
  String id,
) {
  final target = id.trim().toLowerCase();
  for (final interface in interfaces) {
    final candidates = [
      interface.id?.toString() ?? '',
      interface.interfaceName,
      interface.description,
    ];
    if (candidates.any((value) => value.trim().toLowerCase() == target)) {
      return interface;
    }
  }
  return null;
}

_Ipv4Subnet? _subnetForInterface(ManagedInterfaceResource? interface) {
  if (interface == null ||
      interface.ipv4Address.isEmpty ||
      interface.ipv4Prefix == null) {
    return null;
  }
  final address = _ipv4ToInt(interface.ipv4Address);
  final prefix = interface.ipv4Prefix!;
  if (address == null || prefix < 0 || prefix > 32) return null;
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final network = address & mask;
  final broadcast = network | (~mask & 0xFFFFFFFF);
  return _Ipv4Subnet(network, broadcast);
}

_Ipv4Range? _rangeForResource(ManagedDhcpResource resource) {
  final from = _ipv4ToInt(resource.rangeFrom);
  final to = _ipv4ToInt(resource.rangeTo);
  return from == null || to == null ? null : _Ipv4Range(from, to);
}

bool _sameResource(
  ManagedDhcpResource resource,
  ManagedDhcpResource? editing,
) {
  if (editing == null || resource.kind != editing.kind) return false;
  return resource.id?.toString() == editing.id?.toString() &&
      resource.parentId == editing.parentId;
}

int? _ipv4ToInt(String value) {
  final address = InternetAddress.tryParse(value.trim());
  if (address == null || address.type != InternetAddressType.IPv4) return null;
  final parts = address.address.split('.').map(int.parse).toList();
  return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
}

bool _isIpv4(String value) => _ipv4ToInt(value) != null;

bool _isIpv6(String value) {
  final address = InternetAddress.tryParse(value.trim());
  return address?.type == InternetAddressType.IPv6;
}

bool _isHostname(String value) {
  final text = value.trim();
  if (text.isEmpty || text.length > 255) return false;
  return text.split('.').every(
        (part) => part.isNotEmpty &&
            part.length <= 63 &&
            RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
                .hasMatch(part),
      );
}

bool _isMac(String value) {
  return RegExp(r'^[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}$')
      .hasMatch(value.trim());
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = _text(value);
  if (text.isEmpty) return const [];
  return text
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _text(Object? value) => value?.toString().trim() ?? '';

int? _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

bool _isEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  return false;
}

String _label(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

class _Ipv4Range {
  const _Ipv4Range(this.from, this.to);

  final int from;
  final int to;

  bool containsValue(int value) => value >= from && value <= to;
  bool overlaps(_Ipv4Range other) => from <= other.to && other.from <= to;
}

class _Ipv4Subnet {
  const _Ipv4Subnet(this.network, this.broadcast);

  final int network;
  final int broadcast;

  bool containsHost(int value) => value > network && value < broadcast;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
