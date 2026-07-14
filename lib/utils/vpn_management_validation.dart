import 'dart:convert';
import 'dart:io';

import '../models/pfrest_capabilities.dart';
import '../models/vpn_management.dart';

class VpnValidationResult {
  const VpnValidationResult(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String get summary => isValid ? 'Valid' : errors.values.first;
}

class VpnValidationContext {
  const VpnValidationContext({
    this.resources = const [],
    this.editing,
  });

  final List<ManagedVpnResource> resources;
  final ManagedVpnResource? editing;
}

Map<String, dynamic> normaliseVpnValues({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final result = <String, dynamic>{};
  for (final entry in values.entries) {
    final field = operation.field(entry.key, location: 'body');
    var value = entry.value;
    if (value is String) {
      value = value.trim();
      if (field?.type == 'integer' && value.isNotEmpty) {
        value = int.tryParse(value) ?? value;
      } else if (field?.type == 'number' && value.isNotEmpty) {
        value = num.tryParse(value) ?? value;
      } else if ((field?.type == 'array' || field?.type == 'object') &&
          value.isNotEmpty) {
        try {
          value = jsonDecode(value);
        } on FormatException {
          if (field?.type == 'array') {
            value = _splitValues(value);
          }
        }
      }
    } else if (value is List) {
      value = value.map(_normaliseNested).toList(growable: false);
    } else if (value is Map) {
      value = value.map(
        (key, child) => MapEntry(key.toString(), _normaliseNested(child)),
      );
    }
    result[entry.key] = value;
  }
  return result;
}

VpnValidationResult validateVpnResource({
  required VpnResourceKind kind,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  required bool editing,
  VpnValidationContext context = const VpnValidationContext(),
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors, editing: editing);

  if (kind == VpnResourceKind.openVpnServer) {
    _validateOpenVpnServer(values, errors, editing: editing);
  } else if (kind == VpnResourceKind.openVpnClient) {
    _validateOpenVpnClient(values, errors, editing: editing);
  } else if (kind == VpnResourceKind.openVpnCso) {
    _validateOpenVpnCso(values, errors);
  } else if (kind == VpnResourceKind.ipsecPhase1) {
    _validateIpsecPhase1(values, errors, editing: editing);
  } else if (kind == VpnResourceKind.ipsecPhase2) {
    _validateIpsecPhase2(values, errors);
  } else if (kind == VpnResourceKind.wireGuardTunnel) {
    _validateWireGuardTunnel(values, errors, editing: editing);
  } else if (kind == VpnResourceKind.wireGuardPeer) {
    _validateWireGuardPeer(values, errors, editing: editing);
  } else if (kind == VpnResourceKind.wireGuardTunnelAddress ||
      kind == VpnResourceKind.wireGuardPeerAllowedIp) {
    _validateWireGuardNetwork(values, errors, tunnelAddress: kind == VpnResourceKind.wireGuardTunnelAddress);
  }

  _validateDuplicates(kind, values, context, errors);
  return VpnValidationResult(Map.unmodifiable(errors));
}

VpnValidationResult validateVpnSettings({
  required VpnTechnology technology,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors, editing: true);
  if (technology == VpnTechnology.wireGuard &&
    !_boolean(values['resolve_interval_track'])) {
  final resolveInterval = _integer(values['resolve_interval']);
  if (resolveInterval != null && resolveInterval < 1) {
    errors['resolve_interval'] =
        'Resolve interval must be at least 1 second.';
  }
}
  return VpnValidationResult(Map.unmodifiable(errors));
}

VpnValidationResult validateOpenVpnExport({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors, editing: false);
  if (_text(values['server']).isEmpty) {
    errors['server'] = 'Select an OpenVPN server.';
  }
  if (_text(values['type']).isEmpty) {
    errors['type'] = 'Select an export type.';
  }
  return VpnValidationResult(Map.unmodifiable(errors));
}

void _validateOpenVpnServer(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool editing,
}) {
  _validatePort(values, 'local_port', errors);
  _validateSubnetIfPresent(values, 'tunnel_network', errors, ipv6: false);
  _validateSubnetIfPresent(values, 'tunnel_networkv6', errors, ipv6: true);
  _validateSubnetList(values, 'local_network', errors);
  _validateSubnetList(values, 'local_networkv6', errors);
  _validateSubnetList(values, 'remote_network', errors);
  _validateSubnetList(values, 'remote_networkv6', errors);
  if (_boolean(values['use_tls']) &&
      !editing &&
      _text(values['tls']).isEmpty) {
    errors['tls'] = 'Enter or generate a TLS key.';
  }
}

void _validateOpenVpnClient(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool editing,
}) {
  final server = _text(values['server_addr']);
  if (server.isNotEmpty && !_isIpOrHostname(server)) {
    errors['server_addr'] = 'Enter a valid server IP address or hostname.';
  }
  for (final name in const ['server_port', 'local_port', 'proxy_port']) {
    _validatePort(values, name, errors);
  }
  if (_text(values['proxy_authtype']) != 'none' &&
      _text(values['proxy_user']).isEmpty) {
    errors['proxy_user'] = 'Enter the proxy username.';
  }
  if (_text(values['proxy_authtype']) != 'none' &&
      !editing &&
      _text(values['proxy_passwd']).isEmpty) {
    errors['proxy_passwd'] = 'Enter the proxy password.';
  }
  if (_text(values['auth_user']).isNotEmpty &&
      !editing &&
      _text(values['auth_pass']).isEmpty) {
    errors['auth_pass'] = 'Enter the OpenVPN account password.';
  }
  _validateSubnetIfPresent(values, 'tunnel_network', errors, ipv6: false);
  _validateSubnetIfPresent(values, 'tunnel_networkv6', errors, ipv6: true);
  _validateSubnetList(values, 'remote_network', errors);
  _validateSubnetList(values, 'remote_networkv6', errors);
}

void _validateOpenVpnCso(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final commonName = _text(values['common_name']);
  if (commonName.isEmpty) {
    errors['common_name'] = 'Enter a certificate common name or username.';
  }
  for (final name in const [
    'tunnel_network',
    'tunnel_networkv6',
    'local_network',
    'local_networkv6',
    'remote_network',
    'remote_networkv6',
  ]) {
    _validateSubnetList(values, name, errors);
  }
}

void _validateIpsecPhase1(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool editing,
}) {
  final gateway = _text(values['remote_gateway']);
  if (gateway.isNotEmpty && !_isIpOrHostname(gateway)) {
    errors['remote_gateway'] = 'Enter a valid remote gateway or hostname.';
  }
  if (_text(values['authentication_method']) == 'pre_shared_key' &&
      !editing &&
      _text(values['pre_shared_key']).isEmpty) {
    errors['pre_shared_key'] = 'Enter the IPsec pre-shared key.';
  }
  _validatePort(values, 'ikeport', errors);
  _validatePort(values, 'nattport', errors);
  final encryption = values['encryption'];
  if (encryption is! List || encryption.isEmpty) {
    errors['encryption'] = 'Add at least one Phase 1 encryption proposal.';
  }
  final lifetime = _integer(values['lifetime']);
  final rekey = _integer(values['rekey_time']);
  if (lifetime != null && rekey != null && rekey > lifetime) {
    errors['rekey_time'] = 'Rekey time cannot exceed the Phase 1 lifetime.';
  }
}

void _validateIpsecPhase2(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  if (_text(values['ikeid']).isEmpty && _text(values['parent_id']).isEmpty) {
    errors['ikeid'] = 'Select the parent Phase 1 entry.';
  }
  final encryption = values['encryption'];
  if (encryption is! List || encryption.isEmpty) {
    errors['encryption'] = 'Add at least one Phase 2 encryption proposal.';
  }
  for (final name in const [
    'localid_address',
    'remoteid_address',
  ]) {
    final value = _text(values[name]);
    if (value.isNotEmpty && !_isIpOrSubnet(value)) {
      errors[name] = 'Enter a valid address or subnet.';
    }
  }
}

void _validateWireGuardTunnel(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool editing,
}) {
  _validatePort(values, 'listenport', errors);
  if (!editing && !_isWireGuardKey(_text(values['privatekey']))) {
    errors['privatekey'] = 'Enter a valid WireGuard private key.';
  } else if (_text(values['privatekey']).isNotEmpty &&
      !_isWireGuardKey(_text(values['privatekey']))) {
    errors['privatekey'] = 'Enter a valid WireGuard private key.';
  }
  _validateNestedNetworks(values['addresses'], errors, 'addresses', minimumMask: 1);
}

void _validateWireGuardPeer(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool editing,
}) {
  if (!_isWireGuardKey(_text(values['publickey']))) {
    errors['publickey'] = 'Enter a valid WireGuard peer public key.';
  }
  final preShared = _text(values['presharedkey']);
  if (preShared.isNotEmpty && !_isWireGuardKey(preShared)) {
    errors['presharedkey'] = 'Enter a valid WireGuard pre-shared key.';
  }
  final endpoint = _text(values['endpoint']);
  if (endpoint.isNotEmpty && !_isIpOrHostname(endpoint)) {
    errors['endpoint'] = 'Enter a valid endpoint IP address or hostname.';
  }
  if (endpoint.isNotEmpty) _validatePort(values, 'port', errors);
  final keepalive = _integer(values['persistentkeepalive']);
  if (keepalive != null && (keepalive < 0 || keepalive > 65535)) {
    errors['persistentkeepalive'] =
        'Persistent keepalive must be between 0 and 65535 seconds.';
  }
  _validateNestedNetworks(values['allowedips'], errors, 'allowedips');
}

void _validateWireGuardNetwork(
  Map<String, dynamic> values,
  Map<String, String> errors, {
  required bool tunnelAddress,
}) {
  if (_text(values['parent_id']).isEmpty) {
    errors['parent_id'] = 'Select the parent WireGuard resource.';
  }
  final address = InternetAddress.tryParse(_text(values['address']));
  if (address == null) {
    errors['address'] = 'Enter a valid IPv4 or IPv6 address.';
    return;
  }
  final mask = _integer(values['mask']);
  final maximum = address.type == InternetAddressType.IPv4 ? 32 : 128;
  final minimum = tunnelAddress ? 1 : 0;
  if (mask == null || mask < minimum || mask > maximum) {
    errors['mask'] = 'The prefix length must be between $minimum and $maximum.';
  }
}

void _validateNestedNetworks(
  Object? value,
  Map<String, String> errors,
  String field, {
  int minimumMask = 0,
}) {
  if (value == null) return;
  if (value is! List) {
    errors[field] = 'Enter a JSON array of address and mask objects.';
    return;
  }
  final seen = <String>{};
  for (final item in value) {
    if (item is! Map) {
      errors[field] = 'Every entry must be an object with address and mask.';
      return;
    }
    final address = InternetAddress.tryParse(_text(item['address']));
    final mask = _integer(item['mask']);
    if (address == null) {
      errors[field] = 'Every entry must contain a valid IP address.';
      return;
    }
    final maximum = address.type == InternetAddressType.IPv4 ? 32 : 128;
    if (mask == null || mask < minimumMask || mask > maximum) {
      errors[field] =
          'Every prefix length must be between $minimumMask and $maximum.';
      return;
    }
    if (!seen.add('${address.address}/$mask')) {
      errors[field] = 'Duplicate address entries are not allowed.';
      return;
    }
  }
}

void _validateDuplicates(
  VpnResourceKind kind,
  Map<String, dynamic> values,
  VpnValidationContext context,
  Map<String, String> errors,
) {
  for (final resource in context.resources) {
    if (resource.kind != kind || _sameResource(resource, context.editing)) {
      continue;
    }
    if (kind == VpnResourceKind.openVpnCso &&
        _sameText(resource.raw['common_name'], values['common_name'])) {
      errors['common_name'] = 'This client-specific override already exists.';
      return;
    }
    if (kind == VpnResourceKind.ipsecPhase1 &&
        !_boolean(values['gw_duplicates']) &&
        _sameText(resource.raw['remote_gateway'], values['remote_gateway']) &&
        !resource.disabled) {
      errors['remote_gateway'] =
          'An enabled Phase 1 entry already uses this remote gateway.';
      return;
    }
    if (kind == VpnResourceKind.wireGuardPeer &&
        _sameText(resource.raw['publickey'], values['publickey'])) {
      errors['publickey'] = 'This WireGuard public key is already configured.';
      return;
    }
    if (kind == VpnResourceKind.wireGuardTunnelAddress ||
        kind == VpnResourceKind.wireGuardPeerAllowedIp) {
      if (resource.parentId == _text(values['parent_id']) &&
          _sameText(resource.raw['address'], values['address']) &&
          _sameText(resource.raw['mask'], values['mask'])) {
        errors['address'] = 'This address and prefix already exists.';
        return;
      }
    }
  }
}

void _validateSchema(
  Map<String, dynamic> values,
  PfRestOperationCapability operation,
  Map<String, String> errors, {
  required bool editing,
}) {
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body' || field.readOnly) continue;
    final value = values[field.name];
    final secret = isVpnSecretField(field);
    if (field.required && _isEmpty(value) && !(editing && secret)) {
      errors[field.name] = '${_label(field.name)} is required.';
      continue;
    }
    if (_isEmpty(value)) continue;

    if (field.type == 'integer' || field.type == 'number') {
      final number = value is num ? value : num.tryParse(value.toString());
      if (number == null) {
        errors[field.name] = '${_label(field.name)} must be a number.';
      } else if (!field.permitsNumber(number)) {
        errors[field.name] = '${_label(field.name)} is outside the allowed range.';
      }
    }
    if (field.type == 'array' && value is! List) {
      errors[field.name] = '${_label(field.name)} must be a list.';
    }
    if (field.type == 'object' && value is! Map) {
      errors[field.name] = '${_label(field.name)} must be an object.';
    }
    if (value is String) {
      if (field.minLength != null && value.length < field.minLength!) {
        errors[field.name] = '${_label(field.name)} is too short.';
      }
      if (field.maxLength != null && value.length > field.maxLength!) {
        errors[field.name] = '${_label(field.name)} is too long.';
      }
      if (field.pattern != null &&
          field.pattern!.isNotEmpty &&
          !RegExp(field.pattern!).hasMatch(value)) {
        errors[field.name] = '${_label(field.name)} has an invalid format.';
      }
    }
    if (field.allowedValues.isNotEmpty &&
        !field.allowedValues
            .map((item) => item?.toString())
            .contains(value.toString())) {
      errors[field.name] = '${_label(field.name)} is not supported.';
    }
  }
}

void _validatePort(
  Map<String, dynamic> values,
  String name,
  Map<String, String> errors,
) {
  final text = _text(values[name]);
  if (text.isEmpty) return;
  final port = _integer(values[name]);
  if (port == null || port < 1 || port > 65535) {
    errors[name] = 'Enter a port between 1 and 65535.';
  }
}

void _validateSubnetIfPresent(
  Map<String, dynamic> values,
  String name,
  Map<String, String> errors, {
  required bool ipv6,
}) {
  final text = _text(values[name]);
  if (text.isEmpty) return;
  if (!_isSubnet(text, ipv6: ipv6)) {
    errors[name] = ipv6
        ? 'Enter a valid IPv6 subnet in CIDR notation.'
        : 'Enter a valid IPv4 subnet in CIDR notation.';
  }
}

void _validateSubnetList(
  Map<String, dynamic> values,
  String name,
  Map<String, String> errors,
) {
  final valuesList = _stringList(values[name]);
  for (final value in valuesList) {
    if (!_isIpOrSubnet(value)) {
      errors[name] = 'Every entry must be a valid IP address or subnet.';
      return;
    }
  }
}

bool _isSubnet(String value, {bool? ipv6}) {
  final parts = value.trim().split('/');
  if (parts.length != 2) return false;
  final address = InternetAddress.tryParse(parts.first);
  final prefix = int.tryParse(parts.last);
  if (address == null || prefix == null) return false;
  if (ipv6 == true && address.type != InternetAddressType.IPv6) return false;
  if (ipv6 == false && address.type != InternetAddressType.IPv4) return false;
  final maximum = address.type == InternetAddressType.IPv4 ? 32 : 128;
  return prefix >= 0 && prefix <= maximum;
}

bool _isIpOrSubnet(String value) {
  return InternetAddress.tryParse(value.trim()) != null || _isSubnet(value);
}

bool _isIpOrHostname(String value) {
  return InternetAddress.tryParse(value.trim()) != null || _isHostname(value);
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

bool _isWireGuardKey(String value) {
  return RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value.trim());
}

bool _sameResource(
  ManagedVpnResource resource,
  ManagedVpnResource? editing,
) {
  if (editing == null || resource.kind != editing.kind) return false;
  return resource.id?.toString() == editing.id?.toString() &&
      resource.parentId == editing.parentId;
}

bool _sameText(Object? first, Object? second) {
  return _text(first).toLowerCase() == _text(second).toLowerCase();
}

dynamic _normaliseNested(dynamic value) {
  if (value is String) return value.trim();
  if (value is List) return value.map(_normaliseNested).toList(growable: false);
  if (value is Map) {
    return value.map(
      (key, child) => MapEntry(key.toString(), _normaliseNested(child)),
    );
  }
  return value;
}

List<String> _splitValues(String value) {
  return value
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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
  return _splitValues(text);
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
