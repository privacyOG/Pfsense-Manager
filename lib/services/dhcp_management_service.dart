import '../models/dhcp_management.dart';
import '../models/pfrest_capabilities.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class DhcpManagementService {
  DhcpManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  DhcpManagementCapabilities get capabilities =>
      DhcpManagementCapabilities.from(_capabilityService.current);

  Future<List<ManagedDhcpResource>> list(DhcpResourceKind kind) async {
    final operation = _require(kind, 'GET', collection: true);
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      _records(response.data)
          .map((record) => ManagedDhcpResource.fromJson(kind, record)),
    );
  }

  Future<ManagedDhcpResource> create(
    DhcpResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _require(kind, 'POST');
    final draft = ManagedDhcpResource(kind: kind, raw: values);
    final response = await _client.post(
      operation.path,
      data: draft.writablePayload(
        operation,
        changes: values,
        includeIdentifiers: true,
      ),
    );
    return _resourceFromResponse(kind, response.data, fallback: draft);
  }

  Future<ManagedDhcpResource> update(
    ManagedDhcpResource resource,
    Map<String, dynamic> changes,
  ) async {
    final operation = _require(resource.kind, 'PATCH');
    final response = await _client.patch(
      operation.path,
      data: resource.writablePayload(
        operation,
        changes: changes,
        includeIdentifiers: true,
      ),
    );
    return _resourceFromResponse(
      resource.kind,
      response.data,
      fallback: ManagedDhcpResource(
        kind: resource.kind,
        raw: {...resource.raw, ...changes},
      ),
    );
  }

  Future<void> delete(ManagedDhcpResource resource) async {
    final operation = _require(resource.kind, 'DELETE');
    final query = resource.identifierQuery(operation);
    if (query.isEmpty) {
      throw ArgumentError(
        'The ${resource.kind.singularLabel} identifiers are unavailable.',
      );
    }
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<DhcpSingletonConfiguration> getRelay() async {
    final operation = capabilities.relayRead;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('DHCP relay');
    }
    final response = await _client.get(operation.path);
    final records = _records(response.data);
    return DhcpSingletonConfiguration(
      records.isEmpty ? const {} : records.first,
    );
  }

  Future<DhcpSingletonConfiguration> updateRelay(
    DhcpSingletonConfiguration relay,
    Map<String, dynamic> changes,
  ) async {
    final operation = capabilities.relayUpdate;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Update DHCP relay');
    }
    final payload = relay.writablePayload(operation, changes);
    final response = await _client.patch(operation.path, data: payload);
    final records = _records(response.data);
    return DhcpSingletonConfiguration(
      records.isEmpty ? {...relay.raw, ...changes} : records.first,
    );
  }

  Future<void> switchBackend(String backend) async {
    final operation = capabilities.backendUpdate;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('DHCP backend selection');
    }
    final field = operation.field('dhcpbackend', location: 'body');
    if (field == null) {
      throw const UnsupportedApiFeatureException('DHCP backend selection');
    }
    await _client.patch(operation.path, data: {'dhcpbackend': backend});
  }

  Future<bool> hasPendingChanges() async {
    final operation = capabilities.applyRead;
    if (operation == null) return false;
    final response = await _client.get(operation.path);
    final data = response.data is Map ? response.data['data'] : null;
    if (data is bool) return data;
    if (data is Map) {
      for (final key in const ['pending', 'dirty', 'changes_pending']) {
        final value = data[key];
        if (value is bool) return value;
        final text = value?.toString().trim().toLowerCase();
        if (text == 'true' || text == '1' || text == 'yes') return true;
      }
    }
    return false;
  }

  Future<void> apply() async {
    final operation = capabilities.applyWrite;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Apply DHCP server changes');
    }
    await _client.post(operation.path);
  }

  PfRestOperationCapability operationFor(
    DhcpResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    return _require(kind, method, collection: collection);
  }

  PfRestOperationCapability _require(
    DhcpResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    final path = collection ? kind.collectionPath : kind.itemPath;
    final operation = _capabilityService.current.operation(path, method);
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        '${method.toUpperCase()} ${kind.singularLabel}',
      );
    }
    return operation;
  }

  List<Map<String, dynamic>> _records(dynamic responseData) {
    final data = responseData is Map ? responseData['data'] : null;
    if (data is List) {
      return data
          .whereType<Map>()
          .map(
            (record) => record.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false);
    }
    if (data is Map) {
      return [
        data.map((key, value) => MapEntry(key.toString(), value)),
      ];
    }
    return const [];
  }

  ManagedDhcpResource _resourceFromResponse(
    DhcpResourceKind kind,
    dynamic responseData, {
    required ManagedDhcpResource fallback,
  }) {
    final records = _records(responseData);
    if (records.isEmpty) return fallback;
    return ManagedDhcpResource.fromJson(kind, records.first);
  }
}
