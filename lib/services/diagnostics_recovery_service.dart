import '../models/diagnostics_recovery.dart';
import '../models/pfrest_capabilities.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class DiagnosticsRecoveryService {
  DiagnosticsRecoveryService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  DiagnosticsRecoveryCapabilities get capabilities =>
      DiagnosticsRecoveryCapabilities.from(_capabilityService.current);

  Future<List<ArpTableEntry>> listArpEntries() async {
    final operation = _require(capabilities.arpList, 'ARP table');
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      diagnosticsRecords(response.data).map(ArpTableEntry.new),
    );
  }

  Future<void> deleteArpEntry(ArpTableEntry entry) async {
    final operation = _require(
      capabilities.arpDeleteEntry,
      'Delete ARP table entry',
    );
    final query = diagnosticsIdentifierQuery(
      operation: operation,
      id: entry.id,
      raw: entry.raw,
    );
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<void> clearArpTable() async {
    final operation = _require(capabilities.arpClear, 'Clear ARP table');
    await _client.delete(operation.path);
  }

  Future<List<PfTableSnapshot>> listPfTables() async {
    final operation = _require(capabilities.tablesList, 'pf tables');
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      diagnosticsRecords(response.data).map(PfTableSnapshot.new),
    );
  }

  Future<PfTableSnapshot?> readPfTable(String name) async {
    final operation = _require(capabilities.tableRead, 'pf table');
    final query = diagnosticsIdentifierQuery(
      operation: operation,
      id: name,
      raw: {'name': name},
    );
    final response = await _client.get(
      operation.path,
      queryParameters: query,
    );
    final records = diagnosticsRecords(response.data);
    return records.isEmpty ? null : PfTableSnapshot(records.first);
  }

  Future<void> flushPfTable(PfTableSnapshot table) async {
    final operation = _require(capabilities.tableFlush, 'Flush pf table');
    final query = diagnosticsIdentifierQuery(
      operation: operation,
      id: table.name,
      raw: table.raw,
    );
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<List<ConfigHistoryRevision>> listConfigRevisions() async {
    final operation = _require(
      capabilities.revisionsList,
      'Configuration history',
    );
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      diagnosticsRecords(response.data).map(ConfigHistoryRevision.new),
    );
  }

  Future<ConfigHistoryRevision?> readConfigRevision(
    ConfigHistoryRevision revision,
  ) async {
    final operation = _require(
      capabilities.revisionRead,
      'Configuration revision',
    );
    final query = diagnosticsIdentifierQuery(
      operation: operation,
      id: revision.id,
      raw: revision.raw,
    );
    final response = await _client.get(
      operation.path,
      queryParameters: query,
    );
    final records = diagnosticsRecords(response.data);
    return records.isEmpty ? null : ConfigHistoryRevision(records.first);
  }

  Future<void> deleteConfigRevision(ConfigHistoryRevision revision) async {
    final operation = _require(
      capabilities.revisionDelete,
      'Delete configuration revision',
    );
    final query = diagnosticsIdentifierQuery(
      operation: operation,
      id: revision.id,
      raw: revision.raw,
    );
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<void> rollbackConfigRevision(ConfigHistoryRevision revision) async {
    final operation = _require(
      capabilities.rollback,
      'Restore configuration revision',
    );
    final values = <String, dynamic>{
      ...revision.raw,
      'id': revision.id,
      'revision': revision.id,
      'revision_id': revision.id,
      'time': revision.unixTime,
    };
    final body = _valuesForLocation(operation, values, 'body');
    final query = _valuesForLocation(operation, values, 'query');
    if (query.isNotEmpty) {
      throw UnsupportedApiFeatureException(
        'Configuration rollback requires a body-based restore operation.',
      );
    }
    switch (operation.method) {
      case 'POST':
        await _client.post(operation.path, data: body.isEmpty ? null : body);
      case 'PATCH':
        await _client.patch(operation.path, data: body.isEmpty ? null : body);
      default:
        throw UnsupportedApiFeatureException(
          '${operation.method} configuration rollback',
        );
    }
  }

  Future<void> haltSystem() async {
    final operation = _require(capabilities.halt, 'System halt');
    await _client.post(operation.path);
  }

  Future<CommandPromptResult> runCommand(
    String command, {
    required bool explicitlyUnlocked,
  }) async {
    if (!explicitlyUnlocked) {
      throw StateError(
        'The command prompt must be explicitly enabled for this session.',
      );
    }
    final trimmed = command.trim();
    if (trimmed.isEmpty) throw ArgumentError('Command cannot be empty.');
    if (trimmed.length > 4096) {
      throw ArgumentError('Command cannot exceed 4096 characters.');
    }

    final operation = _require(
      capabilities.commandPrompt,
      'Command prompt',
    );
    PfRestFieldConstraint? commandField;
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() == 'body' &&
          !field.readOnly &&
          field.name == 'command') {
        commandField = field;
        break;
      }
    }
    if (commandField == null) {
      throw UnsupportedApiFeatureException(
        'Command prompt request schema',
      );
    }

    final response = await _client.post(
      operation.path,
      data: {commandField.name: trimmed},
    );
    final records = diagnosticsRecords(response.data);
    final record = records.isEmpty ? const <String, dynamic>{} : records.first;
    final output = redactDiagnosticOutput(
      record['output']?.toString() ?? '',
      sensitiveValues: [
        _client.profile.password,
        _client.profile.apiKey,
      ],
    );
    final resultCode = switch (record['result_code']) {
      final int value => value,
      final num value => value.toInt(),
      final Object value => int.tryParse(value.toString()),
      null => null,
    };
    return CommandPromptResult(output: output, resultCode: resultCode);
  }

  PfRestOperationCapability _require(
    PfRestOperationCapability? operation,
    String label,
  ) {
    if (operation == null) throw UnsupportedApiFeatureException(label);
    return operation;
  }

  Map<String, dynamic> _valuesForLocation(
    PfRestOperationCapability operation,
    Map<String, dynamic> values,
    String location,
  ) {
    final result = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != location || field.readOnly) continue;
      final value = values[field.name];
      if (value != null && value.toString().trim().isNotEmpty) {
        result[field.name] = value;
      }
    }
    return result;
  }
}