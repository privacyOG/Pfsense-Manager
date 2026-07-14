import 'dart:io';

import '../models/pfrest_capabilities.dart';
import '../models/routing_management.dart';

class RoutingValidationResult {
  const RoutingValidationResult(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String get summary => isValid
      ? 'Valid'
      : errors.values.first;
}

Map<String, dynamic> normaliseRoutingValues(
  RoutingResourceKind kind,
  Map<String, dynamic> values,
) {
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
      }).toList(growable: false);
    } else {
      result[entry.key] = value;
    }
  }

  for (final key in _integerFields(kind)) {
    final value = result[key];
    if (value is String && value.isNotEmpty) {
      result[key] = int.tryParse(value) ?? value;
    }
  }
  return result;
}

RoutingValidationResult validateRoutingValues({
  required RoutingResourceKind kind,
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  Map<String, String> gatewayFamilies = const {},
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);

  switch (kind) {
    case RoutingResourceKind.gateway:
      _validateGateway(values, errors);
    case RoutingResourceKind.gatewayGroup:
      _validateGatewayGroup(values, gatewayFamilies, errors);
    case RoutingResourceKind.staticRoute:
      _validateStaticRoute(values, gatewayFamilies, errors);
  }

  return RoutingValidationResult(Map.unmodifiable(errors));
}

RoutingValidationResult validateDefaultGatewayValues({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  Map<String, String> gatewayFamilies = const {},
}) {
  final errors = <String, String>{};
  _validateSchema(values, operation, errors);
  for (final entry in const {
    'defaultgw4': 'inet',
    'defaultgw6': 'inet6',
  }.entries) {
    final value = _text(values[entry.key]);
    if (value.isEmpty || value == '-') continue;
    final family = gatewayFamilies[value];
    if (family != null && family != entry.value) {
      errors[entry.key] = entry.value == 'inet'
          ? 'Select an IPv4 gateway or gateway group.'
          : 'Select an IPv6 gateway or gateway group.';
    }
  }
  return RoutingValidationResult(Map.unmodifiable(errors));
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
        final minimum = field.minimum;
        final maximum = field.maximum;
        errors[field.name] = minimum != null && maximum != null
            ? '${_label(field.name)} must be between $minimum and $maximum.'
            : minimum != null
                ? '${_label(field.name)} must be at least $minimum.'
                : '${_label(field.name)} must be no more than $maximum.';
      }
    }

    final text = value is String ? value : null;
    if (text != null) {
      if (field.minLength != null && text.length < field.minLength!) {
        errors[field.name] =
            '${_label(field.name)} must contain at least ${field.minLength} characters.';
      }
      if (field.maxLength != null && text.length > field.maxLength!) {
        errors[field.name] =
            '${_label(field.name)} cannot exceed ${field.maxLength} characters.';
      }
      if (field.pattern != null &&
          field.pattern!.isNotEmpty &&
          !RegExp(field.pattern!).hasMatch(text)) {
        errors[field.name] = '${_label(field.name)} has an invalid format.';
      }
    }

    if (field.allowedValues.isNotEmpty &&
        !field.allowedValues.map((item) => item?.toString()).contains(
              value.toString(),
            )) {
      errors[field.name] = '${_label(field.name)} is not supported.';
    }
  }
}

void _validateGateway(
  Map<String, dynamic> values,
  Map<String, String> errors,
) {
  final name = _text(values['name']);
  if (name.isNotEmpty && !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
    errors['name'] = 'Gateway name may contain only letters, numbers and underscores.';
  }
  if (name.length > 31) {
    errors['name'] = 'Gateway name cannot exceed 31 characters.';
  }

  final family = _text(values['ipprotocol']);
  if (family.isNotEmpty && family != 'inet' && family != 'inet6') {
    errors['ipprotocol'] = 'Select IPv4 or IPv6.';
  }

  final gateway = _text(values['gateway']);
  if (gateway.isNotEmpty && gateway != 'dynamic') {
    final address = InternetAddress.tryParse(gateway);
    if (address == null) {
      errors['gateway'] = 'Enter a valid gateway IP address or dynamic.';
    } else if (family == 'inet' && address.type != InternetAddressType.IPv4) {
      errors['gateway'] = 'An IPv4 gateway requires an IPv4 address.';
    } else if (family == 'inet6' &&
        address.type != InternetAddressType.IPv6) {
      errors['gateway'] = 'An IPv6 gateway requires an IPv6 address.';
    }
  }

  final monitor = _text(values['monitor']);
  final monitorDisabled = _boolean(values['monitor_disable']);
  if (!monitorDisabled && monitor.isNotEmpty) {
    final address = InternetAddress.tryParse(monitor);
    if (address == null) {
      errors['monitor'] = 'Enter a valid monitoring IP address.';
    } else if (family == 'inet' && address.type != InternetAddressType.IPv4) {
      errors['monitor'] = 'An IPv4 gateway requires an IPv4 monitoring address.';
    } else if (family == 'inet6' &&
        address.type != InternetAddressType.IPv6) {
      errors['monitor'] = 'An IPv6 gateway requires an IPv6 monitoring address.';
    }
  }

  _validateHighGreaterThanLow(
    values,
    lowName: 'latencylow',
    highName: 'latencyhigh',
    label: 'latency',
    errors: errors,
  );
  _validateHighGreaterThanLow(
    values,
    lowName: 'losslow',
    highName: 'losshigh',
    label: 'packet-loss',
    errors: errors,
  );
}

void _validateGatewayGroup(
  Map<String, dynamic> values,
  Map<String, String> gatewayFamilies,
  Map<String, String> errors,
) {
  final name = _text(values['name']);
  if (name.isNotEmpty && !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
    errors['name'] =
        'Gateway group name may contain only letters, numbers and underscores.';
  }
  if (name.length > 31) {
    errors['name'] = 'Gateway group name cannot exceed 31 characters.';
  }

  final priorities = values['priorities'];
  if (priorities is! List || priorities.isEmpty) {
    errors['priorities'] = 'Add at least one gateway to the group.';
    return;
  }

  final names = <String>{};
  String? family;
  for (var index = 0; index < priorities.length; index++) {
    final value = priorities[index];
    if (value is! Map) {
      errors['priorities'] = 'Gateway group priorities are invalid.';
      return;
    }
    final gateway = _text(value['gateway']);
    final tier = _integer(value['tier']);
    if (gateway.isEmpty) {
      errors['priorities'] = 'Select a gateway for every priority row.';
      return;
    }
    if (!names.add(gateway)) {
      errors['priorities'] = 'A gateway can appear only once in a group.';
      return;
    }
    if (tier == null || tier < 1 || tier > 5) {
      errors['priorities'] = 'Every gateway tier must be between 1 and 5.';
      return;
    }
    final gatewayFamily = gatewayFamilies[gateway];
    if (gatewayFamily != null) {
      family ??= gatewayFamily;
      if (family != gatewayFamily) {
        errors['priorities'] =
            'All gateways in a group must use the same IP version.';
        return;
      }
    }
  }
}

void _validateStaticRoute(
  Map<String, dynamic> values,
  Map<String, String> gatewayFamilies,
  Map<String, String> errors,
) {
  final network = _text(values['network']);
  String? family;
  if (network.isNotEmpty && network.contains('/')) {
    final pieces = network.split('/');
    final address = pieces.length == 2 ? InternetAddress.tryParse(pieces[0]) : null;
    final prefix = pieces.length == 2 ? int.tryParse(pieces[1]) : null;
    if (address == null || prefix == null) {
      errors['network'] = 'Enter a valid IPv4 or IPv6 network in CIDR notation.';
    } else {
      final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (prefix < 0 || prefix > maxPrefix) {
        errors['network'] = 'The network prefix must be between 0 and $maxPrefix.';
      }
      family = address.type == InternetAddressType.IPv4 ? 'inet' : 'inet6';
    }
  } else if (network.isNotEmpty &&
      !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(network)) {
    errors['network'] = 'Enter a CIDR network or a valid network alias name.';
  }

  final gateway = _text(values['gateway']);
  final gatewayFamily = gatewayFamilies[gateway];
  if (family != null && gatewayFamily != null && family != gatewayFamily) {
    errors['gateway'] =
        'The selected gateway IP version must match the destination network.';
  }
}

void _validateHighGreaterThanLow(
  Map<String, dynamic> values, {
  required String lowName,
  required String highName,
  required String label,
  required Map<String, String> errors,
}) {
  final low = _integer(values[lowName]);
  final high = _integer(values[highName]);
  if (low != null && high != null && high <= low) {
    errors[highName] = 'The high $label threshold must be greater than the low threshold.';
  }
}

Set<String> _integerFields(RoutingResourceKind kind) {
  return switch (kind) {
    RoutingResourceKind.gateway => const {
        'weight',
        'data_payload',
        'latencylow',
        'latencyhigh',
        'losslow',
        'losshigh',
        'interval',
        'loss_interval',
        'time_period',
        'alert_interval',
      },
    RoutingResourceKind.gatewayGroup || RoutingResourceKind.staticRoute =>
      const {},
  };
}

bool _isEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  return false;
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

String _label(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
