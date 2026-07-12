import '../models/firewall_alias.dart';
import 'api_client.dart';

class FirewallAliasService {
  FirewallAliasService(this._client);

  static const collectionPath = '/api/v2/firewall/aliases';
  static const itemPath = '/api/v2/firewall/alias';
  static const applyPath = '/api/v2/firewall/apply';

  final PfSenseApiClient _client;

  Future<List<FirewallAlias>> list() async {
    final response = await _client.get(collectionPath);
    final data = response.data is Map ? response.data['data'] : null;
    final records = data is List ? data : const <dynamic>[];
    final aliases = records
        .whereType<Map<String, dynamic>>()
        .map(FirewallAlias.fromJson)
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(aliases);
  }

  Future<FirewallAlias> create(FirewallAlias alias) async {
    final response = await _client.post(
      itemPath,
      data: alias.toCreatePayload(),
    );
    await _apply();
    return _aliasFromResponse(response.data, fallback: alias);
  }

  Future<FirewallAlias> update(FirewallAlias alias) async {
    final id = alias.id;
    if (id == null) {
      throw ArgumentError('An alias ID is required for updates.');
    }
    final response = await _client.patch(
      itemPath,
      data: {'id': id, ...alias.toUpdatePayload()},
    );
    await _apply();
    return _aliasFromResponse(response.data, fallback: alias);
  }

  Future<void> delete(int id) async {
    await _client.delete(
      itemPath,
      queryParameters: {'id': id.toString()},
    );
    await _apply();
  }

  Future<void> _apply() async {
    await _client.post(applyPath);
  }

  FirewallAlias _aliasFromResponse(
    dynamic responseData, {
    required FirewallAlias fallback,
  }) {
    final data = responseData is Map ? responseData['data'] : null;
    if (data is Map<String, dynamic>) return FirewallAlias.fromJson(data);
    if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
      return FirewallAlias.fromJson(data.first as Map<String, dynamic>);
    }
    return fallback;
  }
}
