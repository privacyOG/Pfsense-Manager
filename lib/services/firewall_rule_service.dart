import '../models/firewall_rule.dart';
import '../models/pfrest_capabilities.dart';
import '../utils/firewall_rule_validation.dart';
import 'api_client.dart';

class FirewallRuleService {
  FirewallRuleService(this._client);

  static const rulesPath = '/api/v2/firewall/rules';
  static const rulePath = '/api/v2/firewall/rule';
  static const applyPath = '/api/v2/firewall/apply';

  final PfSenseApiClient _client;

  Future<List<FirewallRule>> list({String? interface}) async {
    final response = await _client.get(
      rulesPath,
      queryParameters: {
        if (interface != null && interface.trim().isNotEmpty)
          'interface': interface.trim(),
      },
    );
    return _records(response.data)
        .map(FirewallRule.fromJson)
        .toList(growable: false);
  }

  Future<FirewallRule> create(
    FirewallRule rule, {
    PfRestOperationCapability? operation,
  }) async {
    final validation = validateFirewallRule(rule, operation: operation);
    if (!validation.isValid) {
      throw ArgumentError(validation.summary ?? 'Invalid firewall rule.');
    }
    final response = await _client.post(
      rulePath,
      data: rule.toCreatePayload(operation: operation),
    );
    await _apply();
    return _single(response.data, fallback: rule);
  }

  Future<FirewallRule> update(
    FirewallRule rule, {
    PfRestOperationCapability? operation,
  }) async {
    final id = _requiredId(rule);
    final validation = validateFirewallRule(rule, operation: operation);
    if (!validation.isValid) {
      throw ArgumentError(validation.summary ?? 'Invalid firewall rule.');
    }
    final response = await _client.patch(
      rulePath,
      data: {
        'id': id,
        ...rule.toUpdatePayload(operation: operation),
      },
    );
    await _apply();
    return _single(response.data, fallback: rule);
  }

  Future<FirewallRule> setEnabled(
    FirewallRule rule,
    bool enabled, {
    PfRestOperationCapability? operation,
  }) {
    return update(
      rule.copyWith(enabled: enabled),
      operation: operation,
    );
  }

  Future<void> delete(FirewallRule rule) async {
    final id = _requiredId(rule);
    await _client.delete(
      rulePath,
      queryParameters: {'id': id.toString()},
    );
    await _apply();
  }

  Future<void> _apply() => _client.post(applyPath);

  int _requiredId(FirewallRule rule) {
    final id = int.tryParse(rule.id ?? '');
    if (id == null) {
      throw ArgumentError('A numeric firewall rule ID is required.');
    }
    return id;
  }

  List<Map<String, dynamic>> _records(dynamic responseData) {
    final data = _data(responseData);
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  FirewallRule _single(dynamic responseData, {required FirewallRule fallback}) {
    final data = _data(responseData);
    if (data is Map<String, dynamic>) return FirewallRule.fromJson(data);
    if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
      return FirewallRule.fromJson(data.first as Map<String, dynamic>);
    }
    return fallback;
  }

  dynamic _data(dynamic responseData) {
    if (responseData is Map && responseData.containsKey('data')) {
      return responseData['data'];
    }
    return responseData;
  }
}
