import 'dart:io';

import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../models/profile.dart';

enum InterfaceChangeRisk {
  none,
  connectivity,
  managementPath,
}

class InterfaceValidationResult {
  InterfaceValidationResult(Map<String, String> errors)
      : errors = Map.unmodifiable(errors);

  final Map<String, String> errors;
  bool get isValid => errors.isEmpty;
  String? errorFor(String field) => errors[field];
  String get summary => errors.values.join('\n');
}

Map<String, dynamic> normaliseInterfaceValues(
  InterfaceResourceKind kind,
  Map<String, dynamic> values,
) {
  final result = Map<String, dynamic>.from(values);
  if (!kind.isAssigned) return result;

  final typev4 = _text(result['typev4']).toLowerCase();
  result['typev4'] = typev4.isEmpty ? 'none' : typev4;
  switch (result['typev4']) {
    case 'static':
      break;
    case 'dhcp':
      result['ipaddr'] = 'dhcp';
      result['subnet'] = null;
      result['gateway'] = null;
      break;
    case 'pppoe':
      result['ipaddr'] = 'pppoe';
      result['subnet'] = null;
      result['gateway'] = null;
      break;
    default:
      result['typev4'] = 'none';
      result['ipaddr'] = 'none';
      result['subnet'] = null;
      result['gateway'] = null;
  }

  final typev6 = _text(result['typev6']).toLowerCase();
  result['typev6'] = typev6.isEmpty ? 'none' : typev6;
  switch (result['typev6']) {
    case 'static':
      break;
    case 'dhcp6':
    case 'slaac':
    case 'track6':
    case '6rd':
    case '6to4':
      result['ipaddrv6'] = result['typev6'];
      result['subnetv6'] = null;
      result['gatewayv6'] = null;
      break;
    default:
      result['typev6'] = 'none';
      result['ipaddrv6'] = 'none';
      result['subnetv6'] = null;
      result['gatewayv6'] = null;
  }
  return result;
}

InterfaceValidationResult validateInterfaceValues({
  required InterfaceResourceKind kind,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final errors = <String, String>{};
  final normalised = normaliseInterfaceValues(kind, values);

  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body') continue;
    final value = normalised[field.name];
    if (field.required && _isEmpty(value)) {
      errors[field.name] = '${_label(field.name)} is required.';
      continue;
    }
    if (_isEmpty(value)) continue;

    final allowed = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet();
    if (allowed.isNotEmpty && !allowed.contains(value.toString())) {
      errors[field.name] =
          '${_label(field.name)} must be one of ${allowed.join(', ')}.';
    }

    if (field.type == 'integer' || field.type == 'number') {
      final number = num.tryParse(value.toString());
      if (number == null) {
        errors[field.name] = '${_label(field.name)} must be a number.';
      } else if (!field.permitsNumber(number)) {
        final limits = <String>[
          if (field.minimum != null) 'minimum ${field.minimum}',
          if (field.maximum != null) 'maximum ${field.maximum}',
        ].join(', ');
        errors[field.name] = '${_label(field.name)} is outside $limits.';
      }
    }

    if (value is String) {
      if (field.minLength != null && value.length < field.minLength!) {
        errors[field.name] =
            '${_label(field.name)} must contain at least ${field.minLength} characters.';
      }
      if (field.maxLength != null && value.length > field.maxLength!) {
        errors[field.name] =
            '${_label(field.name)} must contain no more than ${field.maxLength} characters.';
      }
    }
  }

  _validateCommon(normalised, errors);
  switch (kind) {
    case InterfaceResourceKind.assigned:
      _validateAssigned(normalised, errors);
      break;
    case InterfaceResourceKind.vlan:
      _validateVlan(normalised, errors);
      break;
    case InterfaceResourceKind.bridge:
    case InterfaceResourceKind.lagg:
      _validateMembers(normalised, errors);
      break;
    case InterfaceResourceKind.gre:
    case InterfaceResourceKind.gif:
      _validateTunnel(normalised, errors);
      break;
  }
  return InterfaceValidationResult(errors);
}

InterfaceChangeRisk interfaceChangeRisk({
  required ManagedInterfaceResource? original,
  required Map<String, dynamic> changes,
  required PfSenseProfile? profile,
}) {
  if (original == null || !original.kind.isAssigned) {
    return InterfaceChangeRisk.none;
  }

  const connectivityFields = {
    'enable',
    'if',
    'typev4',
    'ipaddr',
    'subnet',
    'gateway',
    'typev6',
    'ipaddrv6',
    'subnetv6',
    'gatewayv6',
    'mtu',
    'spoofmac',
  };
  final changedConnectivity = changes.keys.any(connectivityFields.contains);
  if (!changedConnectivity) return InterfaceChangeRisk.none;

  final host = _normaliseHost(profile?.host);
  if (host != null) {
    final currentAddresses = <String>{
      _stripPrefix(original.ipv4Address),
      _stripPrefix(original.ipv6Address),
    }..removeWhere((value) => value.isEmpty || _addressKeyword(value));
    if (currentAddresses.contains(host)) return InterfaceChangeRisk.managementPath;
  }
  return InterfaceChangeRisk.connectivity;
}

void _validateCommon(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  for (final name in const ['mtu', 'mss']) {
    final value = values[name];
    if (_isEmpty(value)) continue;
    final number = int.tryParse(value.toString());
    if (number == null) {
      errors[name] = '${_label(name)} must be a whole number.';
    }
  }

  for (final name in const [
    'ipaddr',
    'ipaddrv6',
    'local',
    'remote',
    'local_addr',
    'remote_addr',
    'tunnel_local_addr',
    'tunnel_remote_addr',
  ]) {
    final value = _text(values[name]);
    if (value.isEmpty || _addressKeyword(value)) continue;
    final address = InternetAddress.tryParse(_stripPrefix(value));
    if (address == null) errors[name] = '${_label(name)} is not a valid IP address.';
  }

  for (final entry in const {'subnet': 32, 'subnetv6': 128}.entries) {
    final value = values[entry.key];
    if (_isEmpty(value)) continue;
    final prefix = int.tryParse(value.toString());
    if (prefix == null || prefix < 0 || prefix > entry.value) {
      errors[entry.key] =
          '${_label(entry.key)} must be between 0 and ${entry.value}.';
    }
  }
}

void _validateAssigned(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  if (_text(values['if']).isEmpty) {
    errors['if'] = 'Interface assignment is required.';
  }
  if (_text(values['descr']).isEmpty) {
    errors['descr'] = 'Description is required.';
  }

  final typev4 = _text(values['typev4']).toLowerCase();
  if (typev4 == 'static') {
    final address = _text(values['ipaddr']);
    if (InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4) {
      errors['ipaddr'] = 'A valid static IPv4 address is required.';
    }
    final prefix = int.tryParse(values['subnet']?.toString() ?? '');
    if (prefix == null || prefix < 1 || prefix > 32) {
      errors['subnet'] = 'IPv4 prefix length must be between 1 and 32.';
    }
  }

  final typev6 = _text(values['typev6']).toLowerCase();
  if (typev6 == 'static') {
    final address = InternetAddress.tryParse(_text(values['ipaddrv6']));
    if (address == null || address.type != InternetAddressType.IPv6) {
      errors['ipaddrv6'] = 'A valid static IPv6 address is required.';
    }
    final prefix = int.tryParse(values['subnetv6']?.toString() ?? '');
    if (prefix == null || prefix < 1 || prefix > 128) {
      errors['subnetv6'] = 'IPv6 prefix length must be between 1 and 128.';
    }
  }

  if (typev6 == 'track6' && _text(values['track6_interface']).isEmpty) {
    errors['track6_interface'] = 'An IPv6 tracking interface is required.';
  }
}

void _validateVlan(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final parent = _text(values['if'] ?? values['parent']);
  if (parent.isEmpty) errors['if'] = 'A VLAN parent interface is required.';
  final tag = int.tryParse(values['tag']?.toString() ?? '');
  if (tag == null || tag < 1 || tag > 4094) {
    errors['tag'] = 'VLAN tag must be between 1 and 4094.';
  }
  final pcpValue = values['pcp'];
  if (!_isEmpty(pcpValue)) {
    final pcp = int.tryParse(pcpValue.toString());
    if (pcp == null || pcp < 0 || pcp > 7) {
      errors['pcp'] = 'VLAN priority must be between 0 and 7.';
    }
  }
}

void _validateMembers(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final raw = values['members'] ?? values['member'];
  final members = raw is List
      ? raw.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList()
      : _text(raw)
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
  if (members.isEmpty) {
    errors['members'] = 'At least one member interface is required.';
  } else if (members.toSet().length != members.length) {
    errors['members'] = 'Member interfaces must be unique.';
  }
}

void _validateTunnel(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final parent = _text(values['if'] ?? values['parent']);
  if (parent.isEmpty) errors['if'] = 'A tunnel parent interface is required.';

  final local = _firstAddress(values, const [
    'local',
    'local_addr',
    'tunnel_local_addr',
  ]);
  final remote = _firstAddress(values, const [
    'remote',
    'remote_addr',
    'tunnel_remote_addr',
  ]);
  if (local == null) errors['local'] = 'A valid local tunnel address is required.';
  if (remote == null) errors['remote'] = 'A valid remote tunnel address is required.';
  if (local != null && remote != null && local.address == remote.address) {
    errors['remote'] = 'Local and remote tunnel addresses must be different.';
  }
}

InternetAddress? _firstAddress(
  Map<String, dynamic> values,
  List<String> names,
) {
  for (final name in names) {
    final text = _text(values[name]);
    if (text.isEmpty) continue;
    return InternetAddress.tryParse(_stripPrefix(text));
  }
  return null;
}

String? _normaliseHost(String? host) {
  final value = host?.trim();
  if (value == null || value.isEmpty) return null;
  final unwrapped = value.startsWith('[') && value.endsWith(']')
      ? value.substring(1, value.length - 1)
      : value;
  return InternetAddress.tryParse(unwrapped)?.address;
}

String _stripPrefix(String value) => value.split('/').first.trim();

bool _addressKeyword(String value) {
  return const {
    'dhcp',
    'dhcp6',
    'none',
    'pppoe',
    'slaac',
    'track6',
    '6rd',
    '6to4',
  }.contains(value.toLowerCase());
}

bool _isEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  return false;
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _label(String name) {
  return name
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
