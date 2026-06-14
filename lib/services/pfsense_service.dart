import '../models/dashboard.dart';
import '../models/dhcp_lease.dart';
import '../models/firewall_rule.dart';
import '../models/firewall_log.dart';
import '../models/network_state.dart';
import '../models/system_service.dart';
import '../models/system_info.dart';
import 'api_client.dart';

/// Service layer for all pfSense API operations.
class PfSenseService {
  final PfSenseApiClient _client;
  final Map<String, int> _serviceIds = {};
  Future<DashboardData>? _dashboardRequest;
  bool _disposed = false;

  PfSenseService(this._client);

  // ==================== DASHBOARD ====================

  Future<DashboardData> getDashboard() {
    _ensureActive();
    final existing = _dashboardRequest;
    if (existing != null) return existing;

    final request = _loadDashboard();
    _dashboardRequest = request;
    request.whenComplete(() {
      if (identical(_dashboardRequest, request)) {
        _dashboardRequest = null;
      }
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

    return DashboardData.fromJson(data).copyWith(
      interfaces: interfacesData
          .whereType<Map<String, dynamic>>()
          .map(InterfaceStatus.fromJson)
          .toList(),
      gateways: gatewaysData
          .whereType<Map<String, dynamic>>()
          .map(GatewayStatus.fromJson)
          .toList(),
    );
  }

  // ==================== FIREWALL RULES ====================

  Future<List<FirewallRule>> getFirewallRules({String? interface}) async {
    _ensureActive();
    final Map<String, dynamic> params = {};
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
    final response = await _client.post(
      '/api/v2/firewall/rules',
      data: ruleData,
    );
    return FirewallRule.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> updateFirewallRule(
    String uuid,
    Map<String, dynamic> ruleData,
  ) async {
    _ensureActive();
    final id = int.tryParse(uuid);
    await _client.patch(
      '/api/v2/firewall/rule',
      data: {
        if (id != null) 'id': id,
        ...ruleData,
      },
    );
  }

  Future<void> deleteFirewallRule(String uuid) async {
    _ensureActive();
    await _client.delete(
      '/api/v2/firewall/rule',
      queryParameters: {'id': uuid},
    );
  }

  Future<void> toggleFirewallRule(String uuid, bool enabled) async {
    _ensureActive();
    await _client.patch(
      '/api/v2/firewall/rule',
      data: {'id': int.tryParse(uuid) ?? uuid, 'disabled': !enabled},
    );
  }

  // ==================== FIREWALL LOGS ====================

  Future<List<FirewallLog>> getFirewallLogs({
    String? action,
    int limit = 100,
    DateTime? since,
  }) async {
    _ensureActive();
    final Map<String, dynamic> params = {'limit': limit.toString()};
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

  // ==================== LIVE NETWORK ====================

  Future<List<NetworkState>> getFirewallStates({int limit = 200}) async {
    _ensureActive();
    final response = await _client.get(
      '/api/v2/firewall/states',
      queryParameters: {'limit': limit.toString()},
    );
    final statesData = response.data['data'] as List? ?? [];
    return statesData
        .whereType<Map<String, dynamic>>()
        .map(NetworkState.fromJson)
        .toList();
  }

  Future<List<InterfaceStatus>> getInterfaceStatuses() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/interfaces');
    final interfacesData = response.data['data'] as List? ?? const [];
    return interfacesData
        .whereType<Map<String, dynamic>>()
        .map(InterfaceStatus.fromJson)
        .toList();
  }

  // ==================== DHCP LEASES ====================

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
    await _client.delete(
      '/api/v2/status/dhcp_server/leases',
      queryParameters: {
        if (lease.ipAddress.isNotEmpty) 'ip': lease.ipAddress,
        if (lease.macAddress.isNotEmpty) 'mac': lease.macAddress,
      },
    );
  }

  // ==================== SERVICES ====================

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

  // ==================== SYSTEM INFO ====================

  Future<SystemInfo> getSystemInfo() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/system');
    return SystemInfo.fromJson(response.data);
  }

  // ==================== VPN ====================

  Future<List<Map<String, dynamic>>> getOpenVPNStatus() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/openvpn/servers');
    return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
  }

  Future<void> restartOpenVPN() async {
    _ensureActive();
    await _client.post(
      '/api/v2/status/service',
      data: await _serviceActionData('openvpn', 'restart'),
    );
  }

  // ==================== REBOOT ====================

  Future<void> rebootSystem() async {
    _ensureActive();
    await _client.post('/api/v2/diagnostics/reboot');
  }

  // ==================== HEALTH CHECK ====================

  Future<bool> healthCheck() async {
    _ensureActive();
    try {
      await _client.get('/api/v2/status/system');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _serviceActionData(
    String serviceName,
    String action,
  ) async {
    _ensureActive();
    if (!_serviceIds.containsKey(serviceName)) {
      await getServices();
    }
    final id = _serviceIds[serviceName];
    return {
      if (id != null) 'id': id,
      'name': serviceName,
      'action': action,
    };
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('This pfSense session is no longer active.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dashboardRequest = null;
    _serviceIds.clear();
    _client.dispose();
  }
}
