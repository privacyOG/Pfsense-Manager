import 'dart:io';

import '../models/firewall_alias.dart';

class FirewallAliasValidationResult {
  const FirewallAliasValidationResult({
    this.nameError,
    this.typeError,
    this.entryErrors = const {},
    this.generalError,
  });

  final String? nameError;
  final String? typeError;
  final Map<int, String> entryErrors;
  final String? generalError;

  bool get isValid =>
      nameError == null &&
      typeError == null &&
      entryErrors.isEmpty &&
      generalError == null;
}

FirewallAliasValidationResult validateFirewallAlias(
  FirewallAlias alias, {
  required Iterable<FirewallAlias> existingAliases,
}) {
  final name = alias.name.trim();
  String? nameError;
  if (name.isEmpty) {
    nameError = 'Alias name is required.';
  } else if (name.length > 31) {
    nameError = 'Alias name must be 31 characters or fewer.';
  } else if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
    nameError = 'Use only letters, numbers and underscores.';
  } else if (RegExp(r'^\d+$').hasMatch(name)) {
    nameError = 'Alias name cannot be entirely numeric.';
  } else if (name.toLowerCase().startsWith('pkg_')) {
    nameError = 'Alias name cannot start with pkg_.';
  } else if (existingAliases.any(
    (item) => item.id != alias.id && item.name.toLowerCase() == name.toLowerCase(),
  )) {
    nameError = 'An alias with this name already exists.';
  }

  final type = alias.type.trim().toLowerCase();
  final typeError = FirewallAlias.supportedTypes.contains(type)
      ? null
      : 'This alias type is not supported for editing.';

  final entryErrors = <int, String>{};
  final seen = <String>{};
  final known = <String, FirewallAlias>{
    for (final item in existingAliases) item.name.toLowerCase(): item,
  };
  var populatedEntries = 0;

  for (var index = 0; index < alias.entries.length; index++) {
    final entry = alias.entries[index];
    final value = entry.value.trim();
    final detail = entry.description.trim();
    if (value.isEmpty && detail.isEmpty) continue;
    if (value.isEmpty) {
      entryErrors[index] = 'Enter a value or remove this row.';
      continue;
    }
    populatedEntries++;
    if (detail.contains('||')) {
      entryErrors[index] = 'Entry descriptions cannot contain ||.';
      continue;
    }
    final identity = value.toLowerCase();
    if (!seen.add(identity)) {
      entryErrors[index] = 'Duplicate alias value.';
      continue;
    }
    if (identity == name.toLowerCase()) {
      entryErrors[index] = 'An alias cannot reference itself.';
      continue;
    }

    final referenced = known[identity];
    final valid = switch (type) {
      'host' => _isHostValue(value, referenced),
      'network' => _isNetworkValue(value, referenced),
      'port' => _isPortValue(value, referenced),
      _ => false,
    };
    if (!valid) {
      entryErrors[index] = switch (type) {
        'host' => 'Use an IP address, FQDN or existing host/network alias.',
        'network' => 'Use a CIDR, FQDN or existing host/network alias.',
        'port' => 'Use a port, ascending port range or existing port alias.',
        _ => 'Unsupported alias value.',
      };
    }
  }

  return FirewallAliasValidationResult(
    nameError: nameError,
    typeError: typeError,
    entryErrors: Map.unmodifiable(entryErrors),
    generalError: populatedEntries == 0
        ? 'Add at least one alias value.'
        : null,
  );
}

bool _isHostValue(String value, FirewallAlias? referenced) {
  if (InternetAddress.tryParse(value) != null) return true;
  if (_isFqdn(value)) return true;
  return referenced != null && referenced.type.toLowerCase() != 'port';
}

bool _isNetworkValue(String value, FirewallAlias? referenced) {
  if (_isCidr(value) || _isFqdn(value)) return true;
  return referenced != null && referenced.type.toLowerCase() != 'port';
}

bool _isPortValue(String value, FirewallAlias? referenced) {
  if (referenced != null && referenced.type.toLowerCase() == 'port') return true;
  final normalized = value.replaceAll(':', '-');
  final parts = normalized.split('-');
  if (parts.length > 2 || parts.any((part) => part.trim().isEmpty)) return false;
  final start = int.tryParse(parts.first.trim());
  final end = int.tryParse(parts.last.trim());
  if (start == null || end == null) return false;
  return start >= 1 && end <= 65535 && start <= end;
}

bool _isCidr(String value) {
  final slash = value.lastIndexOf('/');
  if (slash <= 0 || slash == value.length - 1) return false;
  final address = InternetAddress.tryParse(value.substring(0, slash));
  final prefix = int.tryParse(value.substring(slash + 1));
  if (address == null || prefix == null) return false;
  final maximum = address.type == InternetAddressType.IPv4 ? 32 : 128;
  return prefix >= 0 && prefix <= maximum;
}

bool _isFqdn(String value) {
  if (value.length > 253 || value.endsWith('.')) return false;
  final labels = value.split('.');
  if (labels.length < 2) return false;
  final labelPattern = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
  return labels.every(labelPattern.hasMatch) &&
      !RegExp(r'^\d+$').hasMatch(labels.last);
}
