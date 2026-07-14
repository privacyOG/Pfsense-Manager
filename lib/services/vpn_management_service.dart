import '../models/pfrest_capabilities.dart';
import '../models/vpn_management.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class VpnManagementService {
  VpnManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  VpnManagementCapabilities get capabilities =>
      VpnManagementCapabilities.from(_capabilityService.current);

  Future<List<ManagedVpnResource>> list(
    VpnResourceKind kind, {
    Object? parentId,
  }) async {
    final operation = _require(kind, 'GET', collection: true);
    final query = <String, dynamic>{};
    if (operation.field('parent_id', location: 'query') != null) {
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
          .map((record) => ManagedVpnResource.fromJson(kind, record)),
    );
  }

  Future<ManagedVpnResource> create(
    VpnResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _require(kind, 'POST');
    final payload = buildVpnWritePayload(
      operation: operation,
      changes: values,
      id: values['id'],
      parentId: values['parent_id'],
    );
    final response = await _client.post(operation.path, data: payload);
    final fallback = ManagedVpnResource(kind: kind, raw: values);
    return _resourceFromResponse(kind, response.data, fallback: fallback);
  }

  Future<ManagedVpnResource> update(
    ManagedVpnResource resource,
    Map<String, dynamic> changes,
  ) async {
    final operation = _require(resource.kind, 'PATCH');
    final payload = buildVpnWritePayload(
      operation: operation,
      existing: resource.raw,
      changes: changes,
      id: resource.id,
      parentId: resource.parentId,
    );
    final response = await _client.patch(operation.path, data: payload);
    final fallback = ManagedVpnResource(
      kind: resource.kind,
      raw: {...resource.raw, ...changes},
    );
    return _resourceFromResponse(
      resource.kind,
      response.data,
      fallback: fallback,
    );
  }

  Future<void> delete(ManagedVpnResource resource) async {
    final operation = _require(resource.kind, 'DELETE');
    final query = resource.identifierQuery(operation);
    if (query.isEmpty) {
      throw ArgumentError(
        'The ${resource.kind.singularLabel} identifiers are unavailable.',
      );
    }
    await _client.delete(operation.path, queryParameters: query);
  }

  Future<VpnSingletonSettings> getSettings(
    VpnTechnology technology,
  ) async {
    final operation = capabilities.forTechnology(technology).settingsRead;
    if (operation == null) {
      throw UnsupportedApiFeatureException('${technology.label} settings');
    }
    final response = await _client.get(operation.path);
    final records = _records(response.data);
    return VpnSingletonSettings(records.isEmpty ? const {} : records.first);
  }

  Future<VpnSingletonSettings> updateSettings(
    VpnTechnology technology,
    VpnSingletonSettings settings,
    Map<String, dynamic> changes,
  ) async {
    final operation = capabilities.forTechnology(technology).settingsUpdate;
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        'Update ${technology.label} settings',
      );
    }
    final payload = buildVpnWritePayload(
      operation: operation,
      existing: settings.raw,
      changes: changes,
    );
    final response = await _client.patch(operation.path, data: payload);
    final records = _records(response.data);
    return VpnSingletonSettings(
      records.isEmpty ? {...settings.raw, ...changes} : records.first,
    );
  }

  Future<bool> hasPendingChanges(VpnTechnology technology) async {
    final operation = capabilities.forTechnology(technology).applyRead;
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

  Future<void> apply(VpnTechnology technology) async {
    if (!technology.requiresExplicitApply) return;
    final operation = capabilities.forTechnology(technology).applyWrite;
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        'Apply ${technology.label} changes',
      );
    }
    await _client.post(operation.path);
  }

  Future<VpnExportResult> exportOpenVpnClient(
    Map<String, dynamic> values,
  ) async {
    final operation = capabilities.clientExport;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('OpenVPN client export');
    }
    final payload = buildVpnWritePayload(
      operation: operation,
      changes: values,
    );
    final response = await _client.post(operation.path, data: payload);
    final records = _records(response.data);
    final data = records.isEmpty ? const <String, dynamic>{} : records.first;
    final filename = data['filename']?.toString().trim() ?? '';
    final binaryData = data['binary_data']?.toString() ?? '';
    if (binaryData.isEmpty) {
      throw StateError('The OpenVPN client export returned no file data.');
    }
    return VpnExportResult(
      filename: filename.isEmpty ? 'openvpn-client-export' : filename,
      data: binaryData,
    );
  }

  PfRestOperationCapability operationFor(
    VpnResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    return _require(kind, method, collection: collection);
  }

  PfRestOperationCapability _require(
    VpnResourceKind kind,
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

  ManagedVpnResource _resourceFromResponse(
    VpnResourceKind kind,
    dynamic responseData, {
    required ManagedVpnResource fallback,
  }) {
    final records = _records(responseData);
    if (records.isEmpty) return fallback;
    return ManagedVpnResource.fromJson(kind, records.first);
  }
}
