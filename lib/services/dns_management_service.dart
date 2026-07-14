import '../models/dns_management.dart';
import '../models/pfrest_capabilities.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class DnsManagementService {
  DnsManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  DnsManagementCapabilities get capabilities =>
      DnsManagementCapabilities.from(_capabilityService.current);

  Future<DnsResolverSettings> getResolverSettings() async {
    final operation = capabilities.settingsRead;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('DNS Resolver settings');
    }
    final response = await _client.get(operation.path);
    final records = _records(response.data);
    return DnsResolverSettings(records.isEmpty ? const {} : records.first);
  }

  Future<DnsResolverSettings> updateResolverSettings(
    DnsResolverSettings settings,
    Map<String, dynamic> changes,
  ) async {
    final operation = capabilities.settingsUpdate;
    if (operation == null) {
      throw const UnsupportedApiFeatureException(
        'Update DNS Resolver settings',
      );
    }
    final payload = settings.writablePayload(operation, changes);
    final response = await _client.patch(operation.path, data: payload);
    final records = _records(response.data);
    return DnsResolverSettings(
      records.isEmpty ? {...settings.raw, ...changes} : records.first,
    );
  }

  Future<List<ManagedDnsResource>> list(
    DnsResourceKind kind, {
    Object? parentId,
  }) async {
    final operation = _require(kind, 'GET', collection: true);
    final parentField = operation.field('parent_id', location: 'query');
    final query = <String, dynamic>{};
    if (parentField != null) {
      final value = parentId?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw ArgumentError(
          'A parent identifier is required to list ${kind.label.toLowerCase()}.',
        );
      }
      query['parent_id'] = value;
    }
    final response = await _client.get(
      operation.path,
      queryParameters: query.isEmpty ? null : query,
    );
    return List.unmodifiable(
      _records(response.data)
          .map((record) => ManagedDnsResource.fromJson(kind, record)),
    );
  }

  Future<ManagedDnsResource> create(
    DnsResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _require(kind, 'POST');
    final draft = ManagedDnsResource(kind: kind, raw: values);
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

  Future<ManagedDnsResource> update(
    ManagedDnsResource resource,
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
      fallback: ManagedDnsResource(
        kind: resource.kind,
        raw: {...resource.raw, ...changes},
      ),
    );
  }

  Future<void> delete(ManagedDnsResource resource) async {
    final operation = _require(resource.kind, 'DELETE');
    final query = resource.identifierQuery(operation);
    if (query.isEmpty) {
      throw ArgumentError(
        'The ${resource.kind.singularLabel} identifiers are unavailable.',
      );
    }
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<bool> hasPendingChanges(DnsServiceKind service) async {
    final operation = capabilities.forService(service).applyRead;
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

  Future<void> apply(DnsServiceKind service) async {
    final operation = capabilities.forService(service).applyWrite;
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        'Apply ${service.label} changes',
      );
    }
    await _client.post(operation.path);
  }

  PfRestOperationCapability operationFor(
    DnsResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    return _require(kind, method, collection: collection);
  }

  PfRestOperationCapability _require(
    DnsResourceKind kind,
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

  ManagedDnsResource _resourceFromResponse(
    DnsResourceKind kind,
    dynamic responseData, {
    required ManagedDnsResource fallback,
  }) {
    final records = _records(responseData);
    if (records.isEmpty) return fallback;
    return ManagedDnsResource.fromJson(kind, records.first);
  }
}
