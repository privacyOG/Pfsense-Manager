import 'dart:collection';

import 'pfrest_capabilities.dart';

enum AdministrationSection {
  certificates('Certificates'),
  identities('Users & authentication'),
  apiAccess('API access'),
  system('System maintenance'),
  services('Service settings');

  const AdministrationSection(this.label);

  final String label;
}

enum AdministrationResourceKind {
  certificateAuthorities(
    section: AdministrationSection.certificates,
    label: 'Certificate authorities',
    singularLabel: 'certificate authority',
    collectionPaths: ['/api/v2/system/certificate_authorities'],
    itemPaths: ['/api/v2/system/certificate_authority'],
    highImpact: true,
  ),
  certificates(
    section: AdministrationSection.certificates,
    label: 'Certificates',
    singularLabel: 'certificate',
    collectionPaths: ['/api/v2/system/certificates'],
    itemPaths: ['/api/v2/system/certificate'],
    highImpact: true,
  ),
  revocationLists(
    section: AdministrationSection.certificates,
    label: 'Certificate revocation lists',
    singularLabel: 'certificate revocation list',
    collectionPaths: ['/api/v2/system/crls'],
    itemPaths: ['/api/v2/system/crl'],
    highImpact: true,
  ),
  users(
    section: AdministrationSection.identities,
    label: 'Local users',
    singularLabel: 'local user',
    collectionPaths: ['/api/v2/users'],
    itemPaths: ['/api/v2/user'],
    highImpact: true,
  ),
  groups(
    section: AdministrationSection.identities,
    label: 'Local groups',
    singularLabel: 'local group',
    collectionPaths: ['/api/v2/user/groups'],
    itemPaths: ['/api/v2/user/group'],
    highImpact: true,
  ),
  authenticationServers(
    section: AdministrationSection.identities,
    label: 'Authentication servers',
    singularLabel: 'authentication server',
    collectionPaths: ['/api/v2/user/auth_servers'],
    itemPaths: ['/api/v2/user/auth_server'],
    highImpact: true,
  ),
  apiKeys(
    section: AdministrationSection.apiAccess,
    label: 'REST API keys',
    singularLabel: 'REST API key',
    collectionPaths: ['/api/v2/auth/keys'],
    itemPaths: ['/api/v2/auth/key'],
    highImpact: true,
    basicAuthMutations: true,
  ),
  restApiAccessList(
    section: AdministrationSection.apiAccess,
    label: 'REST API access list',
    singularLabel: 'REST API access-list entry',
    collectionPaths: ['/api/v2/system/restapi/access_list'],
    itemPaths: ['/api/v2/system/restapi/access_list/entry'],
    highImpact: true,
  ),
  restApiSettings(
    section: AdministrationSection.apiAccess,
    label: 'REST API settings',
    singularLabel: 'REST API settings',
    itemPaths: ['/api/v2/system/restapi/settings'],
    singleton: true,
    highImpact: true,
  ),
  tunables(
    section: AdministrationSection.system,
    label: 'System tunables',
    singularLabel: 'system tunable',
    collectionPaths: ['/api/v2/system/tunables'],
    itemPaths: ['/api/v2/system/tunable'],
    highImpact: true,
  ),
  packages(
    section: AdministrationSection.system,
    label: 'Installed packages',
    singularLabel: 'package',
    collectionPaths: ['/api/v2/system/packages'],
    itemPaths: ['/api/v2/system/package'],
    highImpact: true,
  ),
  ntpSettings(
    section: AdministrationSection.services,
    label: 'NTP settings',
    singularLabel: 'NTP settings',
    itemPaths: [
      '/api/v2/services/ntp/settings',
      '/api/v2/services/ntpd/settings',
      '/api/v2/system/ntp',
    ],
    singleton: true,
    highImpact: true,
  ),
  sshSettings(
    section: AdministrationSection.services,
    label: 'SSH settings',
    singularLabel: 'SSH settings',
    itemPaths: [
      '/api/v2/system/ssh',
      '/api/v2/system/ssh/settings',
      '/api/v2/services/ssh/settings',
    ],
    singleton: true,
    highImpact: true,
  ),
  snmpSettings(
    section: AdministrationSection.services,
    label: 'SNMP settings',
    singularLabel: 'SNMP settings',
    itemPaths: [
      '/api/v2/services/snmp',
      '/api/v2/services/snmp/settings',
    ],
    singleton: true,
    highImpact: true,
  ),
  remoteLoggingSettings(
    section: AdministrationSection.services,
    label: 'Remote logging',
    singularLabel: 'remote logging settings',
    itemPaths: [
      '/api/v2/system/remote_logging',
      '/api/v2/system/logging',
      '/api/v2/system/logging/settings',
      '/api/v2/system/syslog',
      '/api/v2/status/system_logs/settings',
    ],
    singleton: true,
    highImpact: true,
  );

  const AdministrationResourceKind({
    required this.section,
    required this.label,
    required this.singularLabel,
    this.collectionPaths = const [],
    required this.itemPaths,
    this.singleton = false,
    this.highImpact = false,
    this.basicAuthMutations = false,
  });

  final AdministrationSection section;
  final String label;
  final String singularLabel;
  final List<String> collectionPaths;
  final List<String> itemPaths;
  final bool singleton;
  final bool highImpact;
  final bool basicAuthMutations;
}

enum AdministrationActionKind {
  generateCertificateAuthority(
    section: AdministrationSection.certificates,
    label: 'Generate certificate authority',
    paths: ['/api/v2/system/certificate_authority/generate'],
    method: 'POST',
    highImpact: true,
  ),
  renewCertificateAuthority(
    section: AdministrationSection.certificates,
    label: 'Renew certificate authority',
    paths: ['/api/v2/system/certificate_authority/renew'],
    method: 'POST',
    highImpact: true,
  ),
  generateCertificate(
    section: AdministrationSection.certificates,
    label: 'Generate certificate',
    paths: ['/api/v2/system/certificate/generate'],
    method: 'POST',
    highImpact: true,
  ),
  renewCertificate(
    section: AdministrationSection.certificates,
    label: 'Renew certificate',
    paths: ['/api/v2/system/certificate/renew'],
    method: 'POST',
    highImpact: true,
  ),
  createSigningRequest(
    section: AdministrationSection.certificates,
    label: 'Create certificate signing request',
    paths: ['/api/v2/system/certificate/signing_request'],
    method: 'POST',
    secretResult: true,
  ),
  signSigningRequest(
    section: AdministrationSection.certificates,
    label: 'Sign certificate request',
    paths: ['/api/v2/system/certificate/signing_request/sign'],
    method: 'POST',
    highImpact: true,
  ),
  exportPkcs12(
    section: AdministrationSection.certificates,
    label: 'Export PKCS#12 certificate',
    paths: ['/api/v2/system/certificate/pkcs12/export'],
    method: 'POST',
    secretResult: true,
  ),
  availablePackages(
    section: AdministrationSection.system,
    label: 'Available packages',
    paths: ['/api/v2/system/package/available'],
    method: 'GET',
  ),
  updateSystem(
    section: AdministrationSection.system,
    label: 'Update pfSense',
    paths: ['/api/v2/system/update'],
    method: 'POST',
    highImpact: true,
  ),
  syncRestApiSettings(
    section: AdministrationSection.apiAccess,
    label: 'Synchronise REST API settings',
    paths: ['/api/v2/system/restapi/settings/sync'],
    method: 'POST',
    highImpact: true,
  );

  const AdministrationActionKind({
    required this.section,
    required this.label,
    required this.paths,
    required this.method,
    this.highImpact = false,
    this.secretResult = false,
  });

  final AdministrationSection section;
  final String label;
  final List<String> paths;
  final String method;
  final bool highImpact;
  final bool secretResult;
}

class AdministrationResourceCapability {
  const AdministrationResourceCapability({
    required this.kind,
    this.collectionRead,
    this.itemRead,
    this.create,
    this.update,
    this.delete,
    this.replace,
    this.mutationNotice,
  });

  final AdministrationResourceKind kind;
  final PfRestOperationCapability? collectionRead;
  final PfRestOperationCapability? itemRead;
  final PfRestOperationCapability? create;
  final PfRestOperationCapability? update;
  final PfRestOperationCapability? delete;
  final PfRestOperationCapability? replace;
  final String? mutationNotice;

  bool get canRead => kind.singleton ? itemRead != null : collectionRead != null;
  bool get canCreate => create != null;
  bool get canUpdate => update != null || replace != null;
  bool get canDelete => delete != null;
  bool get readOnly => canRead && !canCreate && !canUpdate && !canDelete;
  PfRestOperationCapability? get writeOperation => update ?? replace;
}

class AdministrationActionCapability {
  const AdministrationActionCapability({
    required this.kind,
    this.operation,
  });

  final AdministrationActionKind kind;
  final PfRestOperationCapability? operation;

  bool get available => operation != null;
}

class AdministrationManagementCapabilities {
  AdministrationManagementCapabilities._({
    required Map<AdministrationResourceKind, AdministrationResourceCapability>
        resources,
    required Map<AdministrationActionKind, AdministrationActionCapability>
        actions,
  })  : resources = Map.unmodifiable(resources),
        actions = Map.unmodifiable(actions);

  factory AdministrationManagementCapabilities.from(
    PfRestCapabilities? capabilities, {
    required bool allowBasicAuthMutations,
  }) {
    final resources =
        <AdministrationResourceKind, AdministrationResourceCapability>{};
    for (final kind in AdministrationResourceKind.values) {
      final collectionRead = _firstOperation(
        capabilities,
        kind.collectionPaths,
        'GET',
      );
      final itemRead = _firstOperation(capabilities, kind.itemPaths, 'GET');
      var create = _firstOperation(capabilities, kind.itemPaths, 'POST');
      var delete = _firstOperation(capabilities, kind.itemPaths, 'DELETE');
      final update = _firstOperation(capabilities, kind.itemPaths, 'PATCH');
      final replace = _firstOperation(capabilities, kind.itemPaths, 'PUT');
      String? mutationNotice;
      if (kind.basicAuthMutations && !allowBasicAuthMutations) {
        create = null;
        delete = null;
        mutationNotice =
            'Creating or revoking REST API keys requires a password-authenticated profile because pfREST restricts those operations to HTTP Basic authentication.';
      }
      resources[kind] = AdministrationResourceCapability(
        kind: kind,
        collectionRead: collectionRead,
        itemRead: itemRead,
        create: create,
        update: update,
        delete: delete,
        replace: replace,
        mutationNotice: mutationNotice,
      );
    }

    final actions = <AdministrationActionKind, AdministrationActionCapability>{};
    for (final kind in AdministrationActionKind.values) {
      actions[kind] = AdministrationActionCapability(
        kind: kind,
        operation: _firstOperation(capabilities, kind.paths, kind.method),
      );
    }

    return AdministrationManagementCapabilities._(
      resources: resources,
      actions: actions,
    );
  }

  final Map<AdministrationResourceKind, AdministrationResourceCapability>
      resources;
  final Map<AdministrationActionKind, AdministrationActionCapability> actions;

  AdministrationResourceCapability forResource(
    AdministrationResourceKind kind,
  ) =>
      resources[kind]!;

  AdministrationActionCapability forAction(AdministrationActionKind kind) =>
      actions[kind]!;

  List<AdministrationSection> get readableSections =>
      AdministrationSection.values.where((section) {
        return resources.values.any(
              (capability) =>
                  capability.kind.section == section && capability.canRead,
            ) ||
            actions.values.any(
              (capability) =>
                  capability.kind.section == section && capability.available,
            );
      }).toList(growable: false);

  bool get canReadAnything => readableSections.isNotEmpty;
}

class ManagedAdministrationResource {
  ManagedAdministrationResource({
    required this.kind,
    required Map<String, dynamic> raw,
  }) : raw = UnmodifiableMapView(sanitiseAdministrationMap(raw));

  final AdministrationResourceKind kind;
  final Map<String, dynamic> raw;

  Object? get id =>
      raw['id'] ??
      raw['refid'] ??
      raw['uuid'] ??
      raw['username'] ??
      raw['var'] ??
      raw['name'] ??
      raw['pkg_name'];

  String get displayName {
    for (final field in const [
      'descr',
      'description',
      'name',
      'username',
      'var',
      'pkg_name',
      'shortname',
      'refid',
      'common_name',
      'subject',
    ]) {
      final value = _text(raw[field]);
      if (value.isNotEmpty) return value;
    }
    final identifier = _text(id);
    return identifier.isEmpty ? 'Unnamed ${kind.singularLabel}' : identifier;
  }

  String get summary {
    final values = <String>[];
    for (final field in const [
      'type',
      'caref',
      'issuer',
      'serial',
      'expires',
      'scope',
      'disabled',
      'enable',
      'installed_version',
      'version',
      'value',
    ]) {
      final value = raw[field];
      if (value == null) continue;
      final text = value is bool
          ? switch (field) {
              'disabled' => value ? 'Disabled' : 'Enabled',
              _ => value ? 'Enabled' : 'Disabled',
            }
          : value.toString().trim();
      if (text.isNotEmpty && !values.contains(text)) values.add(text);
      if (values.length == 3) break;
    }
    return values.join(' • ');
  }

  Map<String, dynamic> identifierQuery(PfRestOperationCapability operation) {
    final query = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != 'query') continue;
      final value = switch (field.name) {
        'id' => id,
        _ => raw[field.name],
      };
      if (value != null && value.toString().trim().isNotEmpty) {
        query[field.name] = copyAdministrationValue(value);
      }
    }
    return query;
  }
}

class AdministrationOperationResult {
  AdministrationOperationResult({
    required List<Map<String, dynamic>> safeRecords,
    this.ephemeralSecret,
    this.filename,
  }) : safeRecords = List.unmodifiable(
          safeRecords.map(
            (record) => UnmodifiableMapView(record),
          ),
        );

  factory AdministrationOperationResult.fromResponse(
    dynamic responseData, {
    bool captureSecret = false,
  }) {
    final records = administrationRecords(responseData);
    final raw = records.isEmpty ? const <String, dynamic>{} : records.first;
    return AdministrationOperationResult(
      safeRecords: records.map(sanitiseAdministrationMap).toList(growable: false),
      ephemeralSecret:
          captureSecret ? extractAdministrationSecret(raw) : null,
      filename: _text(raw['filename']).isEmpty ? null : _text(raw['filename']),
    );
  }

  final List<Map<String, dynamic>> safeRecords;
  final String? ephemeralSecret;
  final String? filename;

  Map<String, dynamic> get safeData =>
      safeRecords.isEmpty ? const {} : safeRecords.first;
  bool get hasSecret => ephemeralSecret?.isNotEmpty == true;
}

Map<String, dynamic> buildAdministrationWritePayload({
  required PfRestOperationCapability operation,
  Map<String, dynamic> existing = const {},
  Map<String, dynamic> changes = const {},
  Object? id,
}) {
  final payload = <String, dynamic>{};
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body' || field.readOnly) continue;
    final name = field.name;
    if (isAdministrationSecretField(field)) {
      if (changes.containsKey(name) && !_emptySecret(changes[name])) {
        payload[name] = copyAdministrationValue(changes[name]);
      }
      continue;
    }
    if (changes.containsKey(name)) {
      payload[name] = copyAdministrationValue(changes[name]);
    } else if (existing.containsKey(name)) {
      payload[name] = copyAdministrationValue(existing[name]);
    }
  }

  final idField = operation.field('id', location: 'body');
  if (id != null &&
      idField != null &&
      !idField.readOnly &&
      !payload.containsKey('id')) {
    payload['id'] = copyAdministrationValue(id);
  }
  return payload;
}

bool isAdministrationSecretField(PfRestFieldConstraint field) {
  if (field.writeOnly || field.format?.toLowerCase() == 'password') return true;
  return isAdministrationSecretFieldName(field.name);
}

bool isAdministrationSecretFieldName(String name) {
  final normalised = name.trim().toLowerCase();
  return _administrationSecretFields.contains(normalised) ||
      normalised.endsWith('_password') ||
      normalised.endsWith('_passwd') ||
      normalised.endsWith('_secret') ||
      normalised.endsWith('_private_key') ||
      normalised.endsWith('_token');
}

Map<String, dynamic> sanitiseAdministrationMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    if (isAdministrationSecretFieldName(entry.key)) continue;
    result[entry.key] = _sanitiseValue(entry.value);
  }
  return result;
}

String? extractAdministrationSecret(Map<String, dynamic> source) {
  for (final entry in source.entries) {
    if (isAdministrationSecretFieldName(entry.key)) {
      final text = _text(entry.value);
      if (text.isNotEmpty) return text;
    }
    final nested = entry.value;
    if (nested is Map) {
      final value = extractAdministrationSecret(
        nested.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (value != null) return value;
    }
    if (nested is List) {
      for (final item in nested.whereType<Map>()) {
        final value = extractAdministrationSecret(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (value != null) return value;
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> administrationRecords(dynamic responseData) {
  final data = responseData is Map ? responseData['data'] : null;
  if (data is List) {
    return data
        .whereType<Map>()
        .map(
          (record) =>
              record.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
  if (data is Map) {
    return [data.map((key, value) => MapEntry(key.toString(), value))];
  }
  return const [];
}

Object? copyAdministrationValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), copyAdministrationValue(item)),
    );
  }
  if (value is List) {
    return value.map(copyAdministrationValue).toList(growable: false);
  }
  return value;
}

PfRestOperationCapability? _firstOperation(
  PfRestCapabilities? capabilities,
  List<String> paths,
  String method,
) {
  for (final path in paths) {
    final operation = capabilities?.operation(path, method);
    if (operation != null) return operation;
  }
  return null;
}

Object? _sanitiseValue(Object? value) {
  if (value is Map) {
    return sanitiseAdministrationMap(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  if (value is List) {
    return value.map(_sanitiseValue).toList(growable: false);
  }
  return value;
}

bool _emptySecret(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  return false;
}

String _text(Object? value) => value?.toString().trim() ?? '';

const _administrationSecretFields = <String>{
  'password',
  'password_confirm',
  'passwd',
  'bindpw',
  'privatekey',
  'private_key',
  'prv',
  'key',
  'api_key',
  'secret',
  'token',
  'client_secret',
  'community',
  'serverauthkey',
  'binary_data',
  'pkcs12',
  'p12',
};