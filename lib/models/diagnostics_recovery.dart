import 'dart:collection';

import 'pfrest_capabilities.dart';

class DiagnosticsRecoveryCapabilities {
  const DiagnosticsRecoveryCapabilities({
    this.arpList,
    this.arpDeleteEntry,
    this.arpClear,
    this.tablesList,
    this.tableRead,
    this.tableFlush,
    this.revisionsList,
    this.revisionRead,
    this.revisionDelete,
    this.rollback,
    this.halt,
    this.commandPrompt,
  });

  factory DiagnosticsRecoveryCapabilities.from(PfRestCapabilities? capabilities) {
    return DiagnosticsRecoveryCapabilities(
      arpList: capabilities?.operation(
        '/api/v2/diagnostics/arp_table',
        'GET',
      ),
      arpClear: capabilities?.operation(
        '/api/v2/diagnostics/arp_table',
        'DELETE',
      ),
      arpDeleteEntry: capabilities?.operation(
        '/api/v2/diagnostics/arp_table/entry',
        'DELETE',
      ),
      tablesList: capabilities?.operation(
        '/api/v2/diagnostics/tables',
        'GET',
      ),
      tableRead: capabilities?.operation(
        '/api/v2/diagnostics/table',
        'GET',
      ),
      tableFlush: capabilities?.operation(
        '/api/v2/diagnostics/table',
        'DELETE',
      ),
      revisionsList: capabilities?.operation(
        '/api/v2/diagnostics/config_history/revisions',
        'GET',
      ),
      revisionRead: capabilities?.operation(
        '/api/v2/diagnostics/config_history/revision',
        'GET',
      ),
      revisionDelete: capabilities?.operation(
        '/api/v2/diagnostics/config_history/revision',
        'DELETE',
      ),
      rollback: _firstOperation(
        capabilities,
        const [
          '/api/v2/diagnostics/config_history/revision/restore',
          '/api/v2/diagnostics/config_history/restore',
          '/api/v2/diagnostics/config_history/revert',
        ],
        const ['POST', 'PATCH'],
      ),
      halt: capabilities?.operation(
        '/api/v2/diagnostics/halt_system',
        'POST',
      ),
      commandPrompt: capabilities?.operation(
        '/api/v2/diagnostics/command_prompt',
        'POST',
      ),
    );
  }

  final PfRestOperationCapability? arpList;
  final PfRestOperationCapability? arpDeleteEntry;
  final PfRestOperationCapability? arpClear;
  final PfRestOperationCapability? tablesList;
  final PfRestOperationCapability? tableRead;
  final PfRestOperationCapability? tableFlush;
  final PfRestOperationCapability? revisionsList;
  final PfRestOperationCapability? revisionRead;
  final PfRestOperationCapability? revisionDelete;
  final PfRestOperationCapability? rollback;
  final PfRestOperationCapability? halt;
  final PfRestOperationCapability? commandPrompt;

  bool get canReadArp => arpList != null;
  bool get canMutateArp => arpDeleteEntry != null || arpClear != null;
  bool get canReadTables => tablesList != null;
  bool get canFlushTables => tableFlush != null;
  bool get canReadHistory => revisionsList != null;
  bool get canDeleteRevision => revisionDelete != null;
  bool get canRollback => rollback != null;
  bool get canHalt => halt != null;
  bool get canRunCommands => commandPrompt != null;
  bool get canReadAnything => canReadArp || canReadTables || canReadHistory;
}

class ArpTableEntry {
  ArpTableEntry(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(Map<String, dynamic>.from(raw));

  final Map<String, dynamic> raw;

  Object? get id => raw['id'];
  String get ipAddress => _text(raw['ip_address'] ?? raw['ip-address']);
  String get macAddress => _text(raw['mac_address'] ?? raw['mac-address']);
  String get hostname => _text(raw['hostname'] ?? raw['dnsresolve']);
  String get interfaceName => _text(raw['interface']);
  String get type => _text(raw['type']);
  String get expires => _text(raw['expires']);
  bool get permanent => _boolean(raw['permanent']);

  String get displayName {
    if (hostname.isNotEmpty) return hostname;
    if (ipAddress.isNotEmpty) return ipAddress;
    if (macAddress.isNotEmpty) return macAddress;
    return id == null ? 'ARP entry' : 'ARP entry $id';
  }
}

class PfTableSnapshot {
  PfTableSnapshot(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(Map<String, dynamic>.from(raw));

  final Map<String, dynamic> raw;

  String get name => _text(raw['name'] ?? raw['id']);
  List<String> get entries => _stringList(raw['entries']);
}

class ConfigHistoryRevision {
  ConfigHistoryRevision(Map<String, dynamic> raw)
      : raw = UnmodifiableMapView(_sanitiseHistoryMap(raw));

  final Map<String, dynamic> raw;

  Object? get id => raw['id'];
  int? get unixTime => _integer(raw['time']);
  String get description => _text(raw['description']);
  String get version => _text(raw['version']);
  int get filesize => _integer(raw['filesize']) ?? 0;

  DateTime? get timestamp {
    final value = unixTime;
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();
  }

  String get displayName {
    if (description.isNotEmpty) return description;
    final time = timestamp;
    if (time != null) return time.toIso8601String();
    return id == null ? 'Configuration revision' : 'Revision $id';
  }
}

class CommandPromptResult {
  const CommandPromptResult({
    required this.output,
    required this.resultCode,
  });

  final String output;
  final int? resultCode;

  bool get succeeded => resultCode == null || resultCode == 0;
}

List<Map<String, dynamic>> diagnosticsRecords(dynamic responseData) {
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

Map<String, dynamic> diagnosticsIdentifierQuery({
  required PfRestOperationCapability operation,
  required Object? id,
  Map<String, dynamic> raw = const {},
}) {
  final query = <String, dynamic>{};
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'query') continue;
    final value = switch (field.name) {
      'id' => id,
      'name' => raw['name'] ?? id,
      _ => raw[field.name],
    };
    if (value != null && value.toString().trim().isNotEmpty) {
      query[field.name] = value;
    }
  }
  if (query.isEmpty && id != null) query['id'] = id;
  return query;
}

String redactDiagnosticOutput(
  String output, {
  Iterable<String> sensitiveValues = const [],
}) {
  var redacted = output;
  for (final secret in sensitiveValues) {
    final value = secret.trim();
    if (value.length >= 3) redacted = redacted.replaceAll(value, '[REDACTED]');
  }

  redacted = redacted.replaceAllMapped(
    RegExp(
      r'(authorization\s*:\s*(?:bearer|basic)\s+|x-api-key\s*:\s*)[^\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b(password|passwd|api[_-]?key|token|secret|client_secret)\s*[:=]\s*([^\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[REDACTED]',
  );
  redacted = redacted.replaceAll(
    RegExp(
      r'-----BEGIN [^-\n]*PRIVATE KEY-----[\s\S]*?-----END [^-\n]*PRIVATE KEY-----',
    ),
    '[REDACTED PRIVATE KEY]',
  );
  redacted = redacted.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
    '[REDACTED JWT]',
  );
  return redacted;
}

PfRestOperationCapability? _firstOperation(
  PfRestCapabilities? capabilities,
  List<String> paths,
  List<String> methods,
) {
  for (final path in paths) {
    for (final method in methods) {
      final operation = capabilities?.operation(path, method);
      if (operation != null) return operation;
    }
  }
  return null;
}

Map<String, dynamic> _sanitiseHistoryMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    if (_historyPayloadFields.contains(entry.key.toLowerCase())) continue;
    result[entry.key] = entry.value;
  }
  return result;
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
      .split(RegExp(r'[\r\n\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_text(value));
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  return const {'1', 'true', 'yes', 'on'}
      .contains(_text(value).toLowerCase());
}

String _text(Object? value) => value?.toString().trim() ?? '';

const _historyPayloadFields = <String>{
  'config',
  'configuration',
  'xml',
  'contents',
  'content',
  'backup',
  'file_contents',
};