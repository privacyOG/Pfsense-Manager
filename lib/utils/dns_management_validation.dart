import 'dart:io';

import '../models/dns_management.dart';
import '../models/pfrest_capabilities.dart';

class DnsValidationResult {
  const DnsValidationResult(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String get summary => isValid ? 'Valid' : errors.values.first;
}

class DnsValidationContext {
  const DnsValidationContext({
    this.resources = const [],
    this.editing,
  });

  final List<ManagedDnsResource> resources;
  final ManagedDnsResource? editing;
}

Map<String, dynamic> normaliseDnsValues(Map<String, dynamic> values) {
  final result = <String, dynamic>{};
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) {
      result[entry.key] = value.trim();
    } else if (value is List) {
      result[entry.key] = value.map((item) {
        if (item is Map) {
          return item.map(
            (key, child) => MapEntry(
              key.toString(),
              child is String ? child.trim() : child,
            ),
          );
        }
        return item is String ? item.trim() : item;
      }).where((item) {
        return item is! String || item.isNotEmpty;
      }).toList(growable: false);
    } else {
      result[entry.key] = value;
    }
  }
  for (final key in const ['port', 'tlsport', 'mask']) {
    final value = result[key];
    if (value is String && value.isNotEmpty) {
      result[key] = int.tryParse(value) ?? value;
    }
  }
  return result;
}

DnsValidationResult validateResolverSettings({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);
  _validatePort(values, 'port', errors);
  if (_boolean(values['enablessl'])) {
    if (_text(values['sslcertref']).isEmpty) {
      errors['sslcertref'] = 'Select a certificate when DNS over TLS is enabled.';
    }
    _validatePort(values, 'tlsport', errors);
  }
  if (_boolean(values['python']) &&
      _text(values['python_script']).isEmpty) {
    errors['python_script'] = 'Select a Python module or disable the module.';
  }
  if (_boolean(values['strictout']) &&
      _stringList(values['outgoing_interface']).isEmpty) {
    errors['outgoing_interface'] =
        'Strict outgoing mode requires at least one outgoing interface.';
  }
  return DnsValidationResult(Map.unmodifiable(errors));
}

DnsValidationResult validateDnsResource({
  required DnsResourceKind kind,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  DnsValidationContext context = const DnsValidationContext(),
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);

  switch (kind) {
    case DnsResourceKind.resolverHostOverride:
    case DnsResourceKind.forwarderHostOverride:
      _validateHostOverride(kind, values, context, errors);
    case DnsResourceKind.resolverDomainOverride:
      _validateDomainOverride(values, context, errors);
    case DnsResourceKind.resolverAccessList:
      _validateAccessList(values, context, errors);
    case DnsResourceKind.resolverHostAlias:
    case DnsResourceKind.forwarderHostAlias:
      _validateAlias(kind, values, context, errors);
    case DnsResourceKind.resolverAccessListNetwork:
      _validateNetwork(values, errors);
  }

  return DnsValidationResult(Map.unmodifiable(errors));
}

void _validateHostOverride(
  DnsResourceKind kind,
  Map<String, dynamic> values,
  DnsValidationContext context,
  Map<String, String> errors,
) {
  final host = _text(values['host']);
  final domain = _text(values['domain']);
  if (host.isNotEmpty && !_isHostnamePart(host)) {
    errors['host'] = 'Enter a valid host label.';
  }
  if (!_isDomain(domain)) {
    errors['domain'] = 'Enter a valid domain name.';
  }

  final ips = _stringList(values['ip']);
  if (ips.isEmpty) {
    errors['ip'] = 'Enter at least one IP address.';
  } else if (ips.any((value) => !_isIp(value))) {
    errors['ip'] = 'Every override target must be a valid IPv4 or IPv6 address.';
  } else if (kind == DnsResourceKind.forwarderHostOverride && ips.length > 1) {
    errors['ip'] = 'The DNS Forwarder accepts one IP address per host override.';
  }

  for (final resource in context.resources) {
    if (resource.kind != kind || _sameResource(resource, context.editing)) {
      continue;
    }
    if (resource.host.toLowerCase() == host.toLowerCase() &&
        resource.domain.toLowerCase() == domain.toLowerCase()) {
      errors['host'] = 'This host and domain override already exists.';
      break;
    }
  }

  final aliases = values['aliases'];
  if (aliases is List) {
    final seen = <String>{};
    for (final alias in aliases.whereType<Map>()) {
      final aliasHost = _text(alias['host']);
      final aliasDomain = _text(alias['domain']);
      if (!_isHostnamePart(aliasHost) || !_isDomain(aliasDomain)) {
        errors['aliases'] = 'Every alias must contain a valid host and domain.';
        break;
      }
      final key = '$aliasHost.$aliasDomain'.toLowerCase();
      if (!seen.add(key)) {
        errors['aliases'] = 'A host alias can appear only once.';
        break;
      }
    }
  }
}

void _validateDomainOverride(
  Map<String, dynamic> values,
  DnsValidationContext context,
  Map<String, String> errors,
) {
  final domain = _text(values['domain']);
  if (!_isDomain(domain)) {
    errors['domain'] = 'Enter a valid domain name.';
  }
  if (!_isIp(_text(values['ip']))) {
    errors['ip'] = 'Enter a valid upstream IPv4 or IPv6 address.';
  }
  if (_boolean(values['forward_tls_upstream']) &&
      !_isDomain(_text(values['tls_hostname']))) {
    errors['tls_hostname'] =
        'Enter the upstream TLS hostname when TLS forwarding is enabled.';
  }
  for (final resource in context.resources) {
    if (resource.kind != DnsResourceKind.resolverDomainOverride ||
        _sameResource(resource, context.editing)) {
      continue;
    }
    if (resource.domain.toLowerCase() == domain.toLowerCase()) {
      errors['domain'] = 'This domain override already exists.';
      break;
    }
  }
}

void _validateAccessList(
  Map<String, dynamic> values,
  DnsValidationContext context,
  Map<String, String> errors,
) {
  final name = _text(values['name']);
  if (name.isEmpty) errors['name'] = 'Enter an access-list name.';
  const actions = {
    'allow',
    'deny',
    'refuse',
    'allow snoop',
    'deny nonlocal',
    'refuse nonlocal',
  };
  if (!actions.contains(_text(values['action']))) {
    errors['action'] = 'Select a supported access-list action.';
  }
  final networks = values['networks'];
  if (networks is! List || networks.isEmpty) {
    errors['networks'] = 'Add at least one network to the access list.';
  } else {
    final seen = <String>{};
    for (final network in networks.whereType<Map>()) {
      final childErrors = <String, String>{};
      _validateNetwork(
        network.map((key, value) => MapEntry(key.toString(), value)),
        childErrors,
      );
      if (childErrors.isNotEmpty) {
        errors['networks'] = childErrors.values.first;
        break;
      }
      final key = '${network['network']}/${network['mask']}';
      if (!seen.add(key)) {
        errors['networks'] = 'An access-list network can appear only once.';
        break;
      }
    }
  }
  for (final resource in context.resources) {
    if (resource.kind != DnsResourceKind.resolverAccessList ||
        _sameResource(resource, context.editing)) {
      continue;
    }
    if (resource.name.toLowerCase() == name.toLowerCase()) {
      errors['name'] = 'This access-list name already exists.';
      break;
    }
  }
}

void _validateAlias(
  DnsResourceKind kind,
  Map<String, dynamic> values,
  DnsValidationContext context,
  Map<String, String> errors,
) {
  if (_text(values['parent_id']).isEmpty) {
    errors['parent_id'] = 'Select a parent host override.';
  }
  final host = _text(values['host']);
  final domain = _text(values['domain']);
  if (!_isHostnamePart(host)) errors['host'] = 'Enter a valid host label.';
  if (!_isDomain(domain)) errors['domain'] = 'Enter a valid domain name.';
  for (final resource in context.resources) {
    if (resource.kind != kind || _sameResource(resource, context.editing)) {
      continue;
    }
    if (resource.parentId == _text(values['parent_id']) &&
        resource.host.toLowerCase() == host.toLowerCase() &&
        resource.domain.toLowerCase() == domain.toLowerCase()) {
      errors['host'] = 'This alias already exists for the selected override.';
      break;
    }
  }
}

void _validateNetwork(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  if (values.containsKey('parent_id') &&
      _text(values['parent_id']).isEmpty) {
    errors['parent_id'] = 'Select a parent access list.';
  }
  final address = InternetAddress.tryParse(_text(values['network']));
  final mask = _integer(values['mask']);
  if (address == null) {
    errors['network'] = 'Enter a valid IPv4 or IPv6 network address.';
    return;
  }
  final maximum = address.type == InternetAddressType.IPv4 ? 32 : 128;
  if (mask == null || mask < 0 || mask > maximum) {
    errors['mask'] = 'The prefix length must be between 0 and $maximum.';
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
    if (field.type == 'integer' || field.type == 'number') {
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
        !field.allowedValues
            .map((item) => item?.toString())
            .contains(value.toString())) {
      errors[field.name] = '${_label(field.name)} is not supported.';
    }
  }
}

bool _sameResource(
  ManagedDnsResource resource,
  ManagedDnsResource? editing,
) {
  if (editing == null || resource.kind != editing.kind) return false;
  return resource.id?.toString() == editing.id?.toString() &&
      resource.parentId == editing.parentId;
}

bool _isIp(String value) => InternetAddress.tryParse(value.trim()) != null;

bool _isDomain(String value) {
  final text = value.trim();
  if (text.isEmpty || text.length > 255) return false;
  return text.split('.').every(_isHostnamePart);
}

bool _isHostnamePart(String value) {
  final text = value.trim();
  if (text.isEmpty || text.length > 63) return false;
  return RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
      .hasMatch(text);
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
