import '../models/firewall_nat.dart';
import '../utils/firewall_nat_validation.dart';
import 'api_client.dart';

class FirewallNatService {
  FirewallNatService(this._client);

  static const portForwardsPath = '/api/v2/firewall/nat/port_forwards';
  static const portForwardPath = '/api/v2/firewall/nat/port_forward';
  static const oneToOneMappingsPath =
      '/api/v2/firewall/nat/one_to_one/mappings';
  static const oneToOneMappingPath =
      '/api/v2/firewall/nat/one_to_one/mapping';
  static const outboundModePath = '/api/v2/firewall/nat/outbound/mode';
  static const outboundMappingsPath =
      '/api/v2/firewall/nat/outbound/mappings';
  static const outboundMappingPath =
      '/api/v2/firewall/nat/outbound/mapping';
  static const applyPath = '/api/v2/firewall/apply';

  final PfSenseApiClient _client;

  Future<List<NatPortForward>> listPortForwards() async {
    final response = await _client.get(portForwardsPath);
    return _records(response.data)
        .map(NatPortForward.fromJson)
        .toList(growable: false);
  }

  Future<NatPortForward> createPortForward(NatPortForward rule) async {
    validatePortForward(rule);
    final response = await _client.post(
      portForwardPath,
      data: rule.toPayload(),
    );
    await _apply();
    return _single(
      response.data,
      NatPortForward.fromJson,
      fallback: rule,
    );
  }

  Future<NatPortForward> updatePortForward(NatPortForward rule) async {
    _requireId(rule.id, 'port forward');
    validatePortForward(rule);
    final response = await _client.patch(
      portForwardPath,
      data: rule.toPayload(includeId: true),
    );
    await _apply();
    return _single(
      response.data,
      NatPortForward.fromJson,
      fallback: rule,
    );
  }

  Future<NatPortForward> setPortForwardEnabled(
    NatPortForward rule,
    bool enabled,
  ) {
    return updatePortForward(rule.copyWith(disabled: !enabled));
  }

  Future<void> deletePortForward(int id) async {
    await _delete(portForwardPath, id);
  }

  Future<List<NatOneToOneMapping>> listOneToOneMappings() async {
    final response = await _client.get(oneToOneMappingsPath);
    return _records(response.data)
        .map(NatOneToOneMapping.fromJson)
        .toList(growable: false);
  }

  Future<NatOneToOneMapping> createOneToOneMapping(
    NatOneToOneMapping mapping,
  ) async {
    validateOneToOneMapping(mapping);
    final response = await _client.post(
      oneToOneMappingPath,
      data: mapping.toPayload(),
    );
    await _apply();
    return _single(
      response.data,
      NatOneToOneMapping.fromJson,
      fallback: mapping,
    );
  }

  Future<NatOneToOneMapping> updateOneToOneMapping(
    NatOneToOneMapping mapping,
  ) async {
    _requireId(mapping.id, '1:1 NAT mapping');
    validateOneToOneMapping(mapping);
    final response = await _client.patch(
      oneToOneMappingPath,
      data: mapping.toPayload(includeId: true),
    );
    await _apply();
    return _single(
      response.data,
      NatOneToOneMapping.fromJson,
      fallback: mapping,
    );
  }

  Future<NatOneToOneMapping> setOneToOneEnabled(
    NatOneToOneMapping mapping,
    bool enabled,
  ) {
    return updateOneToOneMapping(mapping.copyWith(disabled: !enabled));
  }

  Future<void> deleteOneToOneMapping(int id) async {
    await _delete(oneToOneMappingPath, id);
  }

  Future<OutboundNatMode> getOutboundMode() async {
    final response = await _client.get(outboundModePath);
    final data = _data(response.data);
    if (data is Map) return OutboundNatMode.parse(data['mode']);
    return OutboundNatMode.parse(data);
  }

  Future<OutboundNatMode> updateOutboundMode(OutboundNatMode mode) async {
    validateOutboundMode(mode);
    final response = await _client.patch(
      outboundModePath,
      data: {'mode': mode.name},
    );
    await _apply();
    final data = _data(response.data);
    if (data is Map) return OutboundNatMode.parse(data['mode']);
    return mode;
  }

  Future<List<NatOutboundMapping>> listOutboundMappings() async {
    final response = await _client.get(outboundMappingsPath);
    return _records(response.data)
        .map(NatOutboundMapping.fromJson)
        .toList(growable: false);
  }

  Future<NatOutboundMapping> createOutboundMapping(
    NatOutboundMapping mapping,
  ) async {
    validateOutboundMapping(mapping);
    final response = await _client.post(
      outboundMappingPath,
      data: mapping.toPayload(),
    );
    await _apply();
    return _single(
      response.data,
      NatOutboundMapping.fromJson,
      fallback: mapping,
    );
  }

  Future<NatOutboundMapping> updateOutboundMapping(
    NatOutboundMapping mapping,
  ) async {
    _requireId(mapping.id, 'outbound NAT mapping');
    validateOutboundMapping(mapping);
    final response = await _client.patch(
      outboundMappingPath,
      data: mapping.toPayload(includeId: true),
    );
    await _apply();
    return _single(
      response.data,
      NatOutboundMapping.fromJson,
      fallback: mapping,
    );
  }

  Future<NatOutboundMapping> setOutboundMappingEnabled(
    NatOutboundMapping mapping,
    bool enabled,
  ) {
    return updateOutboundMapping(mapping.copyWith(disabled: !enabled));
  }

  Future<void> deleteOutboundMapping(int id) async {
    await _delete(outboundMappingPath, id);
  }

  Future<void> _delete(String path, int id) async {
    await _client.delete(path, queryParameters: {'id': id.toString()});
    await _apply();
  }

  Future<void> _apply() => _client.post(applyPath);

  List<Map<String, dynamic>> _records(dynamic responseData) {
    final data = _data(responseData);
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  dynamic _data(dynamic responseData) {
    if (responseData is Map && responseData.containsKey('data')) {
      return responseData['data'];
    }
    return responseData;
  }

  T _single<T>(
    dynamic responseData,
    T Function(Map<String, dynamic>) parse, {
    required T fallback,
  }) {
    final data = _data(responseData);
    if (data is Map<String, dynamic>) return parse(data);
    if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
      return parse(data.first as Map<String, dynamic>);
    }
    return fallback;
  }

  void _requireId(int? id, String label) {
    if (id == null) throw ArgumentError('An ID is required to update $label.');
  }
}
