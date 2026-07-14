import '../models/pfrest_capabilities.dart';
import '../models/routing_management.dart';
import '../utils/api_feature_support.dart';
import 'api_client.dart';
import 'pfrest_capability_service.dart';

class RoutingManagementService {
  RoutingManagementService(
    this._client, {
    required PfRestCapabilityService capabilityService,
  }) : _capabilityService = capabilityService;

  final PfSenseApiClient _client;
  final PfRestCapabilityService _capabilityService;

  RoutingManagementCapabilities get capabilities =>
      RoutingManagementCapabilities.from(_capabilityService.current);

  Future<List<ManagedRoutingResource>> list(RoutingResourceKind kind) async {
    final operation = _require(kind, 'GET', collection: true);
    final response = await _client.get(operation.path);
    return List.unmodifiable(
      _records(response.data)
          .map((record) => ManagedRoutingResource.fromJson(kind, record)),
    );
  }

  Future<ManagedRoutingResource> create(
    RoutingResourceKind kind,
    Map<String, dynamic> values,
  ) async {
    final operation = _require(kind, 'POST');
    final draft = ManagedRoutingResource(kind: kind, raw: values);
    final response = await _client.post(
      operation.path,
      data: draft.writablePayload(operation, changes: values),
    );
    return _resourceFromResponse(kind, response.data, fallback: draft);
  }

  Future<ManagedRoutingResource> update(
    ManagedRoutingResource resource,
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
      fallback: ManagedRoutingResource(
        kind: resource.kind,
        raw: {...resource.raw, ...changes},
      ),
    );
  }

  Future<void> delete(ManagedRoutingResource resource) async {
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

  Future<RoutingDefaults> getDefaults() async {
    final operation = capabilities.defaultRead;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Default gateways');
    }
    final response = await _client.get(operation.path);
    final records = _records(response.data);
    return RoutingDefaults(records.isEmpty ? const {} : records.first);
  }

  Future<RoutingDefaults> updateDefaults(
    RoutingDefaults defaults,
    Map<String, dynamic> changes,
  ) async {
    final operation = capabilities.defaultUpdate;
    if (operation == null) {
      throw const UnsupportedApiFeatureException('Update default gateways');
    }
    final payload = defaults.writablePayload(operation, changes);
    final response = await _client.patch(operation.path, data: payload);
    final records = _records(response.data);
    return RoutingDefaults(
      records.isEmpty ? {...defaults.raw, ...changes} : records.first,
    );
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
      throw const UnsupportedApiFeatureException('Apply routing changes');
    }
    await _client.post(operation.path);
  }

  Future<GatewayDependencyReport> findGatewayDependencies(
    String gatewayName,
  ) async {
    final name = gatewayName.trim();
    if (name.isEmpty) return GatewayDependencyReport();

    final groups = <String>[];
    final routes = <String>[];
    final rules = <String>[];
    final defaults = <String>[];
    final unchecked = <String>{};

    if (capabilities.forKind(RoutingResourceKind.gatewayGroup).canRead) {
      try {
        final resources = await list(RoutingResourceKind.gatewayGroup);
        groups.addAll(
          resources
              .where((resource) => resource.referencedGateways.contains(name))
              .map((resource) => resource.displayName),
        );
      } catch (_) {
        unchecked.add('gateway groups');
      }
    } else {
      unchecked.add('gateway groups');
    }

    if (capabilities.forKind(RoutingResourceKind.staticRoute).canRead) {
      try {
        final resources = await list(RoutingResourceKind.staticRoute);
        routes.addAll(
          resources
              .where((resource) => resource.gatewayName == name)
              .map((resource) => resource.displayName),
        );
      } catch (_) {
        unchecked.add('static routes');
      }
    } else {
      unchecked.add('static routes');
    }

    if (capabilities.canReadDefaults) {
      try {
        final current = await getDefaults();
        if (current.ipv4 == name) defaults.add('IPv4');
        if (current.ipv6 == name) defaults.add('IPv6');
      } catch (_) {
        unchecked.add('default gateways');
      }
    } else {
      unchecked.add('default gateways');
    }

    final firewallOperation = capabilities.firewallRuleRead;
    if (firewallOperation != null) {
      try {
        final response = await _client.get(firewallOperation.path);
        for (final record in _records(response.data)) {
          if (!_containsGateway(record['gateway'], name)) continue;
          final id = record['id']?.toString().trim();
          final descr = record['descr']?.toString().trim();
          rules.add(
            descr != null && descr.isNotEmpty
                ? descr
                : id != null && id.isNotEmpty
                    ? 'Rule $id'
                    : 'Unnamed rule',
          );
        }
      } catch (_) {
        unchecked.add('firewall rules');
      }
    } else {
      unchecked.add('firewall rules');
    }

    return GatewayDependencyReport(
      gatewayGroups: groups,
      staticRoutes: routes,
      firewallRules: rules,
      defaultAssignments: defaults,
      uncheckedSources: unchecked,
    );
  }

  PfRestOperationCapability operationFor(
    RoutingResourceKind kind,
    String method, {
    bool collection = false,
  }) {
    return _require(kind, method, collection: collection);
  }

  PfRestOperationCapability _require(
    RoutingResourceKind kind,
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

  ManagedRoutingResource _resourceFromResponse(
    RoutingResourceKind kind,
    dynamic responseData, {
    required ManagedRoutingResource fallback,
  }) {
    final records = _records(responseData);
    if (records.isEmpty) return fallback;
    return ManagedRoutingResource.fromJson(kind, records.first);
  }
}

bool _containsGateway(Object? value, String gatewayName) {
  if (value is String) return value.trim() == gatewayName;
  if (value is List) {
    return value.any((entry) => _containsGateway(entry, gatewayName));
  }
  if (value is Map) {
    return value.values.any((entry) => _containsGateway(entry, gatewayName));
  }
  return false;
}
