import '../models/captive_portal_session.dart';
import '../models/captive_portal_voucher.dart';
import '../models/dashboard.dart';
import '../models/dhcp_lease.dart';
import '../models/firewall_rule.dart';
import '../models/firewall_log.dart';
import '../models/network_state.dart';
import '../models/smart_drive.dart';
import '../models/system_service.dart';
import '../models/system_info.dart';
import '../models/system_log_entry.dart';
import '../models/top_talker.dart';
import '../models/wireguard_tunnel.dart';
import '../utils/api_exception.dart';
import 'api_client.dart';
import 'top_talker_analyzer.dart';

/// Service layer for all pfSense API operations.
class PfSenseService {
  final PfSenseApiClient _client;
  final Map<String, int> _serviceIds = {};
  Future<DashboardData>? _dashboardRequest;
  final Map<int, Future<List<NetworkState>>> _firewallStateRequests = {};
  Future<List<InterfaceStatus>>? _interfaceStatusRequest;
  final TopTalkerAnalyzer _topTalkerAnalyzer = TopTalkerAnalyzer();
  bool _disposed = false;

  PfSenseService(this._client);

  Future<DashboardData> getDashboard() {
    _ensureActive();
    final existing = _dashboardRequest;
    if (existing != null) return existing;
    final request = _loadDashboard();
    _dashboardRequest = request;
    request.whenComplete(() {
      if (identical(_dashboardRequest, request)) _dashboardRequest = null;
    });
    return request;
  }

  Future<DashboardData> _loadDashboard() async {
    final responses = await Future.wait([
      _client.get('/api/v2/status/system'),
      _client.get('/api/v2/status/interfaces'),
      _client.get('/api/v2/status/gateways'),
    ]);
    _ensureActive();
    final statusResp = responses[0];
    final interfacesResp = responses[1];
    final gatewaysResp = responses[2];
    final data = statusResp.data['data'] as Map<String, dynamic>? ?? {};
    final interfacesData = interfacesResp.data['data'] as List? ?? const [];
    final gatewaysData = gatewaysResp.data['data'] as List? ?? const [];
    final interfaces = interfacesData
        .whereType<Map<String, dynamic>>()
        .map(InterfaceStatus.fromJson)
        .toList();
    return DashboardData.fromJson(data).copyWith(
      interfaces: _sortInterfaceStatuses(interfaces),
      gateways: gatewaysData
          .whereType<Map<String, dynamic>>()
          .map(GatewayStatus.fromJson)
          .toList(),
    );
  }

  Future<List<FirewallRule>> getFirewallRules({String? interface}) async {
    _ensureActive();
    final params = <String, dynamic>{};
    if (interface != null) params['if'] = interface;
    final response = await _client.get(
      '/api/v2/firewall/rules',
      queryParameters: params,
    );
    final rulesData = response.data['data'] as List? ?? [];
    return rulesData
        .map((json) => FirewallRule.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    _ensureActive();
    final response = await _client.post('/api/v2/firewall/rules', data: ruleData);
    return FirewallRule.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> updateFirewallRule(String uuid, Map<String, dynamic> ruleData) async {
    _ensureActive();
    final id = int.tryParse(uuid);
    await _client.patch(
      '/api/v2/firewall/rule',
      data: {if (id != null) 'id': id, ...ruleData},
    );
  }

  Future<void> deleteFirewallRule(String uuid) async {
    _ensureActive();
    await _client.delete('/api/v2/firewall/rule', queryParameters: {'id': uuid});
  }

  Future<void> toggleFirewallRule(String uuid, bool enabled) async {
    _ensureActive();
    await _client.patch(
      '/api/v2/firewall/rule',
      data: {'id': int.tryParse(uuid) ?? uuid, 'disabled': !enabled},
    );
  }

  Future<List<FirewallLog>> getFirewallLogs({
    String? action,
    int limit = 100,
    DateTime? since,
  }) async {
    _ensureActive();
    final params = <String, dynamic>{'limit': limit.toString()};
    if (action != null) params['action'] = action;
    if (since != null) params['since'] = since.toIso8601String();
    final response = await _client.get(
      '/api/v2/status/logs/firewall',
      queryParameters: params,
    );
    final logsData = response.data['data'] as List? ?? [];
    return logsData
        .map((json) => FirewallLog.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<SystemLogEntry>> getSystemLog(
    String logType, {
    int limit = 200,
  }) async {
    _ensureActive();
    final response = await _client.get(
      '/api/v2/status/logs/$logType',
      queryParameters: {'limit': limit.toString()},
    );
    final data = response.data['data'] as List? ?? const [];
    return data.map(SystemLogEntry.fromJson).toList();
  }

  Future<List<TopTalker>> getTopTalkers({int limit = 25}) async {
    _ensureActive();
    final results = await Future.wait([
      getFirewallStates(limit: 1000),
      getInterfaceStatuses(),
    ]);
    _ensureActive();
    return _topTalkerAnalyzer.build(
      states: results[0] as List<NetworkState>,
      interfaces: results[1] as List<InterfaceStatus>,
      limit: limit,
    );
  }

  Future<List<NetworkState>> getFirewallStates({int limit = 200}) {
    _ensureActive();
    final existing = _firewallStateRequests[limit];
    if (existing != null) return existing;
    final request = _loadFirewallStates(limit);
    _firewallStateRequests[limit] = request;
    request.whenComplete(() {
      if (identical(_firewallStateRequests[limit], request)) {
        _firewallStateRequests.remove(limit);
      }
    });
    return request;
  }

  Future<List<NetworkState>> _loadFirewallStates(int limit) async {
    final response = await _client.get(
      '/api/v2/firewall/states',
      queryParameters: {'limit': limit.toString()},
    );
    _ensureActive();
    final statesData = response.data['data'] as List? ?? [];
    return statesData
        .whereType<Map<String, dynamic>>()
        .map(NetworkState.fromJson)
        .toList();
  }

  Future<List<InterfaceStatus>> getInterfaceStatuses() {
    _ensureActive();
    final existing = _interfaceStatusRequest;
    if (existing != null) return existing;
    final request = _loadInterfaceStatuses();
    _interfaceStatusRequest = request;
    request.whenComplete(() {
      if (identical(_interfaceStatusRequest, request)) _interfaceStatusRequest = null;
    });
    return request;
  }

  Future<List<InterfaceStatus>> _loadInterfaceStatuses() async {
    final response = await _client.get('/api/v2/status/interfaces');
    _ensureActive();
    final interfacesData = response.data['data'] as List? ?? const [];
    final interfaces = interfacesData
        .whereType<Map<String, dynamic>>()
        .map(InterfaceStatus.fromJson)
        .toList();
    return _sortInterfaceStatuses(interfaces);
  }

  Future<List<DhcpLease>> getDhcpLeases() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/dhcp_server/leases');
    final leasesData = response.data['data'] as List? ?? [];
    return leasesData
        .whereType<Map<String, dynamic>>()
        .map(DhcpLease.fromJson)
        .toList();
  }

  Future<void> deleteDhcpLease(DhcpLease lease) async {
    _ensureActive();
    await _client.delete('/api/v2/status/dhcp_server/leases', queryParameters: {
      if (lease.ipAddress.isNotEmpty) 'ip': lease.ipAddress,
      if (lease.macAddress.isNotEmpty) 'mac': lease.macAddress,
    });
  }

  Future<List<SystemService>> getServices() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/services');
    final servicesData = response.data['data'] as List? ?? [];
    final services = servicesData
        .map((json) => SystemService.fromJson(json as Map<String, dynamic>))
        .toList();
    _serviceIds
      ..clear()
      ..addEntries(
        services
            .where((service) => service.id != null)
            .map((service) => MapEntry(service.name, service.id!)),
      );
    return services;
  }

  Future<void> startService(String serviceName) async {
    _ensureActive();
    await _client.post(
      '/api/v2/status/service',
      data: await _serviceActionData(serviceName, 'start'),
    );
  }

  Future<void> stopService(String serviceName) async {
    _ensureActive();
    await _client.post(
      '/api/v2/status/service',
      data: await _serviceActionData(serviceName, 'stop'),
    );
  }

  Future<void> restartService(String serviceName) async {
    _ensureActive();
    await _client.post(
      '/api/v2/status/service',
      data: await _serviceActionData(serviceName, 'restart'),
    );
  }

  Future<SystemInfo> getSystemInfo() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/system');
    return SystemInfo.fromJson(response.data);
  }
}

List<InterfaceStatus> _sortInterfaceStatuses(List<InterfaceStatus> interfaces) => interfaces;
