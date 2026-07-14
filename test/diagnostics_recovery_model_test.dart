import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/diagnostics_recovery.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  test('stock diagnostics capabilities use exact pfREST paths', () {
    final operations = <String, PfRestOperationCapability>{
      for (final entry in const [
        ('/api/v2/diagnostics/arp_table', 'GET'),
        ('/api/v2/diagnostics/arp_table/entry', 'DELETE'),
        ('/api/v2/diagnostics/tables', 'GET'),
        ('/api/v2/diagnostics/table', 'DELETE'),
        ('/api/v2/diagnostics/config_history/revisions', 'GET'),
        ('/api/v2/diagnostics/halt_system', 'POST'),
        ('/api/v2/diagnostics/command_prompt', 'POST'),
      ])
        PfRestCapabilities.operationKey(entry.$1, entry.$2):
            _operation(entry.$1, entry.$2),
    };
    final capabilities = DiagnosticsRecoveryCapabilities.from(
      PfRestCapabilities(
        profileId: 'test',
        status: PfRestCapabilityStatus.available,
        operations: operations,
        packageTags: const {},
        loadedAt: DateTime(2026, 7, 14),
      ),
    );

    expect(capabilities.canReadArp, isTrue);
    expect(capabilities.canMutateArp, isTrue);
    expect(capabilities.canReadTables, isTrue);
    expect(capabilities.canFlushTables, isTrue);
    expect(capabilities.canReadHistory, isTrue);
    expect(capabilities.canHalt, isTrue);
    expect(capabilities.canRunCommands, isTrue);
    expect(capabilities.canRollback, isFalse);
  });

  test('pf table browsing requires the collection endpoint', () {
    const path = '/api/v2/diagnostics/table';
    final capabilities = DiagnosticsRecoveryCapabilities.from(
      PfRestCapabilities(
        profileId: 'test',
        status: PfRestCapabilityStatus.available,
        operations: {
          PfRestCapabilities.operationKey(path, 'GET'):
              _operation(path, 'GET'),
        },
        packageTags: const {},
        loadedAt: DateTime(2026, 7, 14),
      ),
    );

    expect(capabilities.tableRead, isNotNull);
    expect(capabilities.canReadTables, isFalse);
  });

  test('rollback is exposed only when a restore alias is reported', () {
    const path = '/api/v2/diagnostics/config_history/revision/restore';
    final capabilities = DiagnosticsRecoveryCapabilities.from(
      PfRestCapabilities(
        profileId: 'test',
        status: PfRestCapabilityStatus.available,
        operations: {
          PfRestCapabilities.operationKey(path, 'POST'):
              _operation(path, 'POST'),
        },
        packageTags: const {},
        loadedAt: DateTime(2026, 7, 14),
      ),
    );

    expect(capabilities.canRollback, isTrue);
    expect(capabilities.rollback!.path, path);
  });

  test('ARP, pf table and revision models preserve runtime identifiers', () {
    final arp = ArpTableEntry(const {
      'id': 4,
      'ip-address': '192.168.1.20',
      'mac-address': '00:11:22:33:44:55',
      'hostname': 'switch.local',
      'interface': 'lan',
      'permanent': true,
    });
    final table = PfTableSnapshot(const {
      'name': 'blocked_hosts',
      'entries': ['192.0.2.10', '2001:db8::10'],
    });
    final revision = ConfigHistoryRevision(const {
      'id': 8,
      'time': 1760000000,
      'description': 'Before routing change',
      'version': '2.8.0',
      'filesize': 4096,
      'config': '<pfsense><password>hidden</password></pfsense>',
      'file_contents': 'hidden-backup',
    });

    expect(arp.id, 4);
    expect(arp.ipAddress, '192.168.1.20');
    expect(arp.displayName, 'switch.local');
    expect(arp.permanent, isTrue);
    expect(table.name, 'blocked_hosts');
    expect(table.entries, ['192.0.2.10', '2001:db8::10']);
    expect(revision.id, 8);
    expect(revision.description, 'Before routing change');
    expect(revision.timestamp, isNotNull);
    expect(revision.raw, isNot(contains('config')));
    expect(revision.raw, isNot(contains('file_contents')));
  });

  test('command output redacts saved and discovered credential material', () {
    const jwt =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiJ9.signature_value';
    final output = redactDiagnosticOutput(
      '''password=super-secret
X-API-Key: generated-key
Authorization: Bearer $jwt
api_key=other-key
-----BEGIN PRIVATE KEY-----
private-material
-----END PRIVATE KEY-----''',
      sensitiveValues: const ['super-secret'],
    );

    expect(output, isNot(contains('super-secret')));
    expect(output, isNot(contains('generated-key')));
    expect(output, isNot(contains('other-key')));
    expect(output, isNot(contains(jwt)));
    expect(output, isNot(contains('private-material')));
    expect(output, contains('[REDACTED]'));
    expect(output, contains('[REDACTED PRIVATE KEY]'));
  });
}

PfRestOperationCapability _operation(String path, String method) {
  return PfRestOperationCapability(
    path: path,
    method: method,
    requestFields: const {},
    tags: const {'DIAGNOSTICS'},
  );
}