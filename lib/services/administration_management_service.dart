import '../models/administration_management.dart';
import '../models/pfrest_capabilities.dart';
import '../models/profile.dart';
import '../utils/api_feature_support.dart';
import 'administration_basic_auth_transport.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class AdministrationManagementService {
  AdministrationManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
    AdministrationBasicAuthTransport? basicAuthTransport,
  })  : _capabilityService = capabilityService,
        _basicAuthTransport =
            basicAuthTransport ?? PfSenseBasicAuthTransport(_client.profile);

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;
  final AdministrationBasicAuthTransport _basicAuthTransport;

  bool get canUseBasicAuthMutations =>
      _client.profile.authMode == PfSenseAuthMode.jwtPassword &&
      _client.profile.username.trim().isNotEmpty &&
      _client.profile.password.isNotEmpty;

  AdministrationManagementCapabilities get capabilities =>
      AdministrationManagementCapabilities.from(
        _capabilityService.current,
        allowBasicAuthMutations: canUseBasicAuthMutations,
      );

  Future<List<ManagedAdministrationResource>> list(
    AdministrationResourceKind kind,
  ) async {
    final capability = capabilities.forResource(kind);
    final operation = kind.singleton
        ? capability.itemRead
        : capability.collectionRead;
    if (operation == null) {
      throw UnsupportedApiFeatureException('Read ${kind.label}');
    }
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      administrationRecords(response.data).map(
        (record) => ManagedAdministrationResource(kind: kind, raw: record),
      ),
    );
  }

  Future<ManagedAdministrationResource?> readSingleton(
    AdministrationResourceKind kind,
  ) async {
    if (!kind.singleton) {
      throw ArgumentError('${kind.label} is not a singleton resource.');
    }
    final records = await list(kind);
    return records.isEmpty ? null : records.first;
  }

  Future<AdministrationOperationResult> create(
    AdministrationResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _requireResource(kind, 'POST');
    final payload = buildAdministrationWritePayload(
      operation: operation,
      changes: values,
      id: values['id'],
    );
    final response = kind.basicAuthMutations
        ? await _basicAuthTransport.post(operation.path, data: payload)
        : await _client.post(operation.path, data: payload);
    return AdministrationOperationResult.fromResponse(
      response.data,
      captureSecret: kind == AdministrationResourceKind.apiKeys,
    );
  }

  Future<AdministrationOperationResult> update(
    ManagedAdministrationResource resource,
    Map<String, dynamic> changes,
  ) async {
    final capability = capabilities.forResource(resource.kind);
    final operation = capability.update ?? capability.replace;
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        'Update ${resource.kind.singularLabel}',
      );
    }
    final payload = buildAdministrationWritePayload(
      operation: operation,
      existing: resource.raw,
      changes: changes,
      id: resource.id,
    );
    final response = operation.method == 'PUT'
        ? await _client.put(operation.path, data: payload)
        : await _client.patch(operation.path, data: payload);
    return AdministrationOperationResult.fromResponse(response.data);
  }

  Future<void> delete(ManagedAdministrationResource resource) async {
    final operation = _requireResource(resource.kind, 'DELETE');
    final query = resource.identifierQuery(operation);
    if (query.isEmpty) {
      throw ArgumentError(
        'The ${resource.kind.singularLabel} identifier is unavailable.',
      );
    }
    if (resource.kind.basicAuthMutations) {
      await _basicAuthTransport.delete(
        operation.path,
        queryParameters: query,
      );
    } else {
      await _client.delete(operation.path, queryParameters: query);
    }
  }

  Future<AdministrationOperationResult> runAction(
    AdministrationActionKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = capabilities.forAction(kind).operation;
    if (operation == null) {
      throw UnsupportedApiFeatureException(kind.label);
    }
    final body = buildAdministrationWritePayload(
      operation: operation,
      changes: values,
      id: values['id'],
    );
    final query = _queryValues(operation, values);
    final response = switch (operation.method) {
      'GET' => await _client.get(
          operation.path,
          queryParameters: query.isEmpty ? null : query,
        ),
      'POST' => await _client.post(
          operation.path,
          data: body.isEmpty ? null : body,
        ),
      'PATCH' => await _client.patch(
          operation.path,
          data: body.isEmpty ? null : body,
        ),
      'PUT' => await _client.put(
          operation.path,
          data: body.isEmpty ? null : body,
        ),
      'DELETE' => await _client.delete(
          operation.path,
          queryParameters: query.isEmpty ? null : query,
        ),
      _ => throw UnsupportedApiFeatureException(
          '${operation.method} ${kind.label}',
        ),
    };
    return AdministrationOperationResult.fromResponse(
      response.data,
      captureSecret: kind.secretResult,
    );
  }

  PfRestOperationCapability operationForResource(
    AdministrationResourceKind kind,
    String method,
  ) =>
      _requireResource(kind, method);

  PfRestOperationCapability operationForAction(AdministrationActionKind kind) {
    final operation = capabilities.forAction(kind).operation;
    if (operation == null) {
      throw UnsupportedApiFeatureException(kind.label);
    }
    return operation;
  }

  PfRestOperationCapability _requireResource(
    AdministrationResourceKind kind,
    String method,
  ) {
    final capability = capabilities.forResource(kind);
    final operation = switch (method.toUpperCase()) {
      'GET' => kind.singleton
          ? capability.itemRead
          : capability.collectionRead,
      'POST' => capability.create,
      'PATCH' => capability.update,
      'PUT' => capability.replace,
      'DELETE' => capability.delete,
      _ => null,
    };
    if (operation == null) {
      throw UnsupportedApiFeatureException(
        '${method.toUpperCase()} ${kind.singularLabel}',
      );
    }
    return operation;
  }

  Map<String, dynamic> _queryValues(
    PfRestOperationCapability operation,
    Map<String, dynamic> values,
  ) {
    final query = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != 'query') continue;
      final value = values[field.name];
      if (value != null && value.toString().trim().isNotEmpty) {
        query[field.name] = copyAdministrationValue(value);
      }
    }
    return query;
  }
}