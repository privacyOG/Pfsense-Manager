import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class InterfaceManagementService {
  InterfaceManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  InterfaceManagementCapabilities get capabilities =>
      InterfaceManagementCapabilities.from(_capabilityService.current);

  Future<List<ManagedInterfaceResource>> list(
    InterfaceResourceKind kind,
  ) async {
    final operation = _require(kind, 'GET', collection: true);
    final response = await _client.get(operation.path);
    final records = _records(response.data);
    return List.unmodifiable(
      records.map((record) => ManagedInterfaceResource.fromJson(kind, record)),
    );
  }

  Future<List<AvailableInterface>> listAvailableInterfaces() async {
    final operation = _capabilityService.current?.operation(
      interfaceAvailablePath,
      'GET',
    );
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Available interfaces');
    }
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      _records(response.data)
          .map(AvailableInterface.fromJson)
          .where((item) => item.name.isNotEmpty),
    );
  }

  Future<ManagedInterfaceResource> create(
    InterfaceResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _require(kind, 'POST');
    final draft = ManagedInterfaceResource(kind: kind, raw: values);
    final response = await _client.post(
      operation.path,
      data: draft.writablePayload(operation, changes: values),
    );
    return _resourceFromResponse(kind, response.data, fallback: draft);
  }

  Future<ManagedInterfaceResource> update(
    ManagedInterfaceResource resource,
    Map<String, dynamic> changes,
  ) async {
    final operation = _require(resource.kind, 'PATCH');
    final payload = resource.writablePayload(
      operation,
      changes: changes,
      includeIdentifier: true,
    );
    final response = await _client.patch(operation.path, data: payload);
    return _resourceFromResponse(
      resource.kind,
      response.data,
      fallback: ManagedInterfaceResource(
        kind: resource.kind,
        raw: {...resource.raw, ...changes},
      ),
    );
  }

  Future<void> delete(ManagedInterfaceResource resource) async {
    final operation = _require(resource.kind, 'DELETE');
    final id = resource.id;
    if (id == null) {
      throw ArgumentError(
        'An identifier is required to delete this ${resource.kind.singularLabel}.',
      );
    }
    final query = resource.identifierQuery(operation);
    await _client.delete(
      operation.path,
      queryParameters: query.isEmpty ? {'id': id.toString()} : query,
    );
  }

  Future<bool> hasPendingChanges() async {
    final operation = _capabilityService.current?.operation(
      interfaceApplyPath,
      'GET',
    );
    if (operation == null) return false;
    final response = await _client.get(operation.path);
    final data = response.data is Map ? response.data['data'] : null;
    if (data is bool) return data;
    if (data is Map) {
      for (final key in const ['pending', 'dirty', 'changes_pending']) {
        final value = data[key];
        if (value is bool) return value;
        final text = value?.toString().toLowerCase();
        if (text == 'true' || text == '1' || text == 'yes') return true;
      }
    }
    return false;
  }

  Future<void> apply() async {
    final operation = _capabilityService.current?.operation(
      interfaceApplyPath,
      'POST',
    );
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Apply interface changes');
    }
    await _client.post(operation.path);
  }

  PfRestOperationCapability operationFor(
    InterfaceResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    return _require(kind, method, collection: collection);
  }

  PfRestOperationCapability _require(
    InterfaceResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    final path = collection ? kind.collectionPath : kind.itemPath;
    final operation = _capabilityService.current?.operation(path, method);
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        '${method.toUpperCase()} ${kind.singularLabel}',
      );
    }
    return operation;
  }

  List<Map<String, dynamic>> _records(dynamic responseData) {
    final data = responseData is Map ? responseData['data'] : null;
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    if (data is Map<String, dynamic>) return [data];
    return const [];
  }

  ManagedInterfaceResource _resourceFromResponse(
    InterfaceResourceKind kind,
    dynamic responseData, {
    required ManagedInterfaceResource fallback,
  }) {
    final records = _records(responseData);
    if (records.isEmpty) return fallback;
    return ManagedInterfaceResource.fromJson(kind, records.first);
  }
}
