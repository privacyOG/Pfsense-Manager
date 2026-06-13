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

  PfSenseService(this._client);

  // ==================== DASHBOARD ====================

  Future<DashboardData> getDashboard() async {
    try {
      final responses = await Future.wait([
        _client.get('/api/v2/status/system'),
        _client.get('/api/v2/status/interfaces'),
        _client.get('/api/v2/status/gateways'),
      ]);
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
    } catch (e) {
      rethrow;
    }
  }

  // ==================== FIREWALL RULES ====================

  Future<List<FirewallRule>> getFirewallRules({String? interface}) async {
    try {
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
    } catch (e) {
      rethrow;
    }
  }

  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    try {
      final response = await _client.post(
        '/api/v2/firewall/rules',
        data: ruleData,
      );
      return FirewallRule.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateFirewallRule(
    String uuid,
    Map<String, dynamic> ruleData,
  ) async {
    try {
      final id = int.tryParse(uuid);
      await _client.patch(
        '/api/v2/firewall/rule',
        data: {
          if (id != null) 'id': id,
          ...ruleData,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteFirewallRule(String uuid) async {
    try {
      await _client.delete(
        '/api/v2/firewall/rule',
        queryParameters: {'id': uuid},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> toggleFirewallRule(String uuid, bool enabled) async {
    try {
      await _client.patch(
        '/api/v2/firewall/rule',
        data: {'id': int.tryParse(uuid) ?? uuid, 'disabled': !enabled},
      );
    } catch (e) {
      rethrow;
    }
  }

  // ==================== FIREWALL LOGS ====================

  Future<List<FirewallLog>> getFirewallLogs({
    String? action,
    int limit = 100,
    DateTime? since,
  }) async {
    try {
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
    } catch (e) {
      rethrow;
    }
  }

  // ==================== LIVE NETWORK ====================

  Future<List<NetworkState>> getFirewallStates({int limit = 200}) async {
    try {
      final response = await _client.get(
        '/api/v2/firewall/states',
        queryParameters: {'limit': limit.toString()},
      );
      final statesData = response.data['data'] as List? ?? [];
      return statesData
          .whereType<Map<String, dynamic>>()
          .map(NetworkState.fromJson)
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<InterfaceStatus>> getInterfaceStatuses() async {
    try {
      final response = await _client.get('/api/v2/status/interfaces');
      final interfacesData = response.data['data'] as List? ?? const [];
      return interfacesData
          .whereType<Map<String, dynamic>>()
          .map(InterfaceStatus.fromJson)
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // ==================== DHCP LEASES ====================

  Future<List<DhcpLease>> getDhcpLeases() async {
    try {
      final response = await _client.get('/api/v2/status/dhcp_server/leases');
      final leasesData = response.data['data'] as List? ?? [];
      return leasesData
          .whereType<Map<String, dynamic>>()
          .map(DhcpLease.fromJson)
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteDhcpLease(DhcpLease lease) async {
    try {
      await _client.delete(
        '/api/v2/status/dhcp_server/leases',
        queryParameters: {
          if (lease.ipAddress.isNotEmpty) 'ip': lease.ipAddress,
          if (lease.macAddress.isNotEmpty) 'mac': lease.macAddress,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  // ==================== SERVICES ====================

  Future<List<SystemService>> getServices() async {
    try {
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
    } catch (e) {
      rethrow;
    }
  }

  Future<void> startService(String serviceName) async {
    try {
      await _client.post(
        '/api/v2/status/service',
        data: await _serviceActionData(serviceName, 'start'),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> stopService(String serviceName) async {
    try {
      await _client.post(
        '/api/v2/status/service',
        data: await _serviceActionData(serviceName, 'stop'),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> restartService(String serviceName) async {
    try {
      await _client.post(
        '/api/v2/status/service',
        data: await _serviceActionData(serviceName, 'restart'),
      );
    } catch (e) {
      rethrow;
    }
  }

  // ==================== SYSTEM INFO ====================

  Future<SystemInfo> getSystemInfo() async {
    try {
      final response = await _client.get('/api/v2/status/system');
      return SystemInfo.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // ==================== VPN ====================

  Future<List<Map<String, dynamic>>> getOpenVPNStatus() async {
    try {
      final response = await _client.get('/api/v2/status/openvpn/servers');
      return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> restartOpenVPN() async {
    try {
      await _client.post(
        '/api/v2/status/service',
        data: await _serviceActionData('openvpn', 'restart'),
      );
    } catch (e) {
      rethrow;
    }
  }

  // ==================== REBOOT ====================

  Future<void> rebootSystem() async {
    try {
      await _client.post('/api/v2/diagnostics/reboot');
    } catch (e) {
      rethrow;
    }
  }

  // ==================== HEALTH CHECK ====================

  Future<bool> healthCheck() async {
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

  void dispose() {
    _client.dispose();
  }
}
