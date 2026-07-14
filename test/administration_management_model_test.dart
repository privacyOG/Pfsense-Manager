import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/administration_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  test('administration resources recursively redact secrets', () {
    final resource = ManagedAdministrationResource(
      kind: AdministrationResourceKind.authenticationServers,
      raw: const {
        'id': 4,
        'name': 'Directory',
        'bindpw': 'hidden',
        'nested': {
          'client_secret': 'hidden-too',
          'safe': 'visible',
        },
        'items': [
          {'private_key': 'hidden-three', 'label': 'visible-two'},
        ],
      },
    );

    expect(resource.raw, isNot(contains('bindpw')));
    expect(resource.raw['nested'], {'safe': 'visible'});
    expect(resource.raw['items'], [
      {'label': 'visible-two'},
    ]);
  });

  test('write payload preserves unknown fields and omits blank secrets', () {
    final operation = _operation(
      '/api/v2/user/auth_server',
      'PATCH',
      fields: const {
        'id': PfRestFieldConstraint(
          name: 'id',
          location: 'body',
          required: true,
          type: 'integer',
        ),
        'name': PfRestFieldConstraint(
          name: 'name',
          location: 'body',
          required: true,
          type: 'string',
        ),
        'bindpw': PfRestFieldConstraint(
          name: 'bindpw',
          location: 'body',
          required: false,
          type: 'string',
          writeOnly: true,
        ),
        'future_setting': PfRestFieldConstraint(
          name: 'future_setting',
          location: 'body',
          required: false,
          type: 'string',
        ),
        'generated': PfRestFieldConstraint(
          name: 'generated',
          location: 'body',
          required: false,
          type: 'string',
          readOnly: true,
        ),
      },
    );

    final payload = buildAdministrationWritePayload(
      operation: operation,
      existing: const {
        'id': 7,
        'name': 'Old directory',
        'future_setting': 'preserve-me',
        'generated': 'do-not-send',
      },
      changes: const {'name': 'New directory', 'bindpw': ''},
      id: 7,
    );

    expect(payload, containsPair('id', 7));
    expect(payload, containsPair('name', 'New directory'));
    expect(payload, containsPair('future_setting', 'preserve-me'));
    expect(payload, isNot(contains('bindpw')));
    expect(payload, isNot(contains('generated')));
  });

  test('API key mutations require a password-authenticated profile', () {
    final operations = <String, PfRestOperationCapability>{
      PfRestCapabilities.operationKey('/api/v2/auth/keys', 'GET'):
          _operation('/api/v2/auth/keys', 'GET'),
      PfRestCapabilities.operationKey('/api/v2/auth/key', 'POST'):
          _operation('/api/v2/auth/key', 'POST'),
      PfRestCapabilities.operationKey('/api/v2/auth/key', 'DELETE'):
          _operation('/api/v2/auth/key', 'DELETE'),
    };
    final snapshot = PfRestCapabilities(
      profileId: 'test',
      status: PfRestCapabilityStatus.available,
      operations: operations,
      packageTags: const {},
      loadedAt: DateTime(2026, 7, 14),
    );

    final restricted = AdministrationManagementCapabilities.from(
      snapshot,
      allowBasicAuthMutations: false,
    ).forResource(AdministrationResourceKind.apiKeys);
    final allowed = AdministrationManagementCapabilities.from(
      snapshot,
      allowBasicAuthMutations: true,
    ).forResource(AdministrationResourceKind.apiKeys);

    expect(restricted.canRead, isTrue);
    expect(restricted.canCreate, isFalse);
    expect(restricted.canDelete, isFalse);
    expect(restricted.mutationNotice, contains('Basic authentication'));
    expect(allowed.canCreate, isTrue);
    expect(allowed.canDelete, isTrue);
  });

  test('operation results expose a secret once but retain only safe records', () {
    final result = AdministrationOperationResult.fromResponse(
      const {
        'data': {
          'id': 3,
          'descr': 'Mobile key',
          'key': 'one-time-secret',
          'nested': {'token': 'hidden', 'safe': 'visible'},
        },
      },
      captureSecret: true,
    );

    expect(result.ephemeralSecret, 'one-time-secret');
    expect(result.safeData, isNot(contains('key')));
    expect(result.safeData['nested'], {'safe': 'visible'});
  });
}

PfRestOperationCapability _operation(
  String path,
  String method, {
  Map<String, PfRestFieldConstraint> fields = const {},
}) {
  return PfRestOperationCapability(
    path: path,
    method: method,
    requestFields: {
      for (final field in fields.values)
        '${field.location}:${field.name}': field,
    },
    tags: const {'SYSTEM'},
  );
}