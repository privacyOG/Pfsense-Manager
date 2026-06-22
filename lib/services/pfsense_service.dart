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
import '../models/top_talker.dart';
import '../models/wireguard_tunnel.dart';
import 'api_client.dart';

/// Service layer for all pfSense API operations.
class PfSenseService {
  final PfSenseApiClient _client;
  final Map<String, int> _serviceIds = {};
  Future<DashboardData>? _dashboardRequest;
  final Map<int, Future<List<NetworkState>>> _firewallStateRequests = {};
  Future<List<InterfaceStatus>>? _interfaceStatusRequest;
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
    return DashboardData.fromJson(data).copyWith(
      interfaces: interfacesData.whereType<Map<String, dynamic>>().map(InterfaceStatus.fromJson).toList(),
      gateways: gatewaysData.whereType<Map<String, dynamic>>().map(GatewayStatus.fromJson).toList(),
    );
  }

  Future<List<FirewallRule>> getFirewallRules({String? interface}) async {
    _ensureActive();
    final params = <String, dynamic>{};
    if (interface != null) params['if'] = interface;
    final response = await _client.get('/api/v2/firewall/rules', queryParameters: params);
    final rulesData = response.data['data'] as List? ?? [];
    return rulesData.map((json) => FirewallRule.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    _ensureActive();
    final response = await _client.post('/api/v2/firewall/rules', data: ruleData);
    return FirewallRule.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> updateFirewallRule(String uuid, Map<String, dynamic> ruleData) async {
    _ensureActive();
    final id = int.tryParse(uuid);
    await _client.patch('/api/v2/firewall/rule', data: {if (id != null) 'id': id, ...ruleData});
  }

  Future<void> deleteFirewallRule(String uuid) async {
    _ensureActive();
    await _client.delete('/api/v2/firewall/rule', queryParameters: {'id': uuid});
  }

  Future<void> toggleFirewallRule(String uuid, bool enabled) async {
    _ensureActive();
    await _client.patch('/api/v2/firewall/rule', data: {'id': int.tryParse(uuid) ?? uuid, 'disabled': !enabled});
  }

  Future<List<FirewallLog>> getFirewallLogs({String? action, int limit = 100, DateTime? since}) async {
    _ensureActive();
    final params = <String, dynamic>{'limit': limit.toString()};
    if (action != null) params['action'] = action;
    if (since != null) params['since'] = since.toIso8601String();
    final response = await _client.get('/api/v2/status/logs/firewall', queryParameters: params);
    final logsData = response.data['data'] as List? ?? [];
    return logsData.map((json) => FirewallLog.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<TopTalker>> getTopTalkers({int limit = 25}) async {
    _ensureActive();
    final states = await getFirewallStates(limit: 1000);
    final map = <String, _TopTalkerAgg>{};
    for (final state in states) {
      final ip = state.sourceIp.split(':').first.trim();
      if (ip.isEmpty || ip == '*') continue;
      final agg = map.putIfAbsent(ip, () => _TopTalkerAgg(ip));
      agg.bytes += state.bytes;
      agg.connections++;
      if (state.interface.isNotEmpty && agg.iface.isEmpty) {
        agg.iface = state.interface;
      }
    }
    final result = map.values
        .map((a) => TopTalker(
              ipAddress: a.ip,
              bytes: a.bytes,
              connections: a.connections,
              interface: a.iface,
            ))
        .toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return result.take(limit).toList();
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
    final response = await _client.get('/api/v2/firewall/states', queryParameters: {'limit': limit.toString()});
    _ensureActive();
    final statesData = response.data['data'] as List? ?? [];
    return statesData.whereType<Map<String, dynamic>>().map(NetworkState.fromJson).toList();
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
    return interfacesData.whereType<Map<String, dynamic>>().map(InterfaceStatus.fromJson).toList();
  }

  Future<List<DhcpLease>> getDhcpLeases() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/dhcp_server/leases');
    final leasesData = response.data['data'] as List? ?? [];
    return leasesData.whereType<Map<String, dynamic>>().map(DhcpLease.fromJson).toList();
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
    final services = servicesData.map((json) => SystemService.fromJson(json as Map<String, dynamic>)).toList();
    _serviceIds
      ..clear()
      ..addEntries(services.where((service) => service.id != null).map((service) => MapEntry(service.name, service.id!)));
    return services;
  }

  Future<void> startService(String serviceName) async {
    _ensureActive();
    await _client.post('/api/v2/status/service', data: await _serviceActionData(serviceName, 'start'));
  }

  Future<void> stopService(String serviceName) async {
    _ensureActive();
    await _client.post('/api/v2/status/service', data: await _serviceActionData(serviceName, 'stop'));
  }

  Future<void> restartService(String serviceName) async {
    _ensureActive();
    await _client.post('/api/v2/status/service', data: await _serviceActionData(serviceName, 'restart'));
  }

  Future<SystemInfo> getSystemInfo() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/system');
    return SystemInfo.fromJson(response.data);
  }

  Future<List<Map<String, dynamic>>> getOpenVPNStatus() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/openvpn/servers');
    return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
  }

  Future<void> restartOpenVPN() async {
    _ensureActive();
    await _client.post('/api/v2/status/service', data: await _serviceActionData('openvpn', 'restart'));
  }

  Future<void> rebootSystem() async {
    _ensureActive();
    await _client.post('/api/v2/diagnostics/reboot');
  }

  Future<List<WireGuardTunnel>> getWireGuardStatus() async {
    _ensureActive();
    try {
      final results = await Future.wait([
        _client.get('/api/v2/vpn/wireguard/servers'),
        _client.get('/api/v2/vpn/wireguard/peers'),
      ]);
      final tunnelData = results[0].data['data'] as List? ?? [];
      final peerData = results[1].data['data'] as List? ?? [];

      return tunnelData.whereType<Map<String, dynamic>>().map((tunnel) {
        final tunnelName = tunnel['name']?.toString() ?? '';
        final peers = peerData.whereType<Map<String, dynamic>>().where((p) {
          final tun = p['tun']?.toString() ?? p['tunnel']?.toString() ?? '';
          return tun == tunnelName || tun.isEmpty;
        }).toList();
        return WireGuardTunnel.fromJson({...tunnel, 'peers': peers});
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<DashboardData> getHardwareHealth() async {
    _ensureActive();
    final response = await _client.get('/api/v2/status/system');
    final data = response.data['data'] as Map<String, dynamic>? ?? {};
    return DashboardData.fromJson(data);
  }

  Future<List<SmartDrive>> getSmartStatus() async {
    _ensureActive();
    try {
      final response = await _client.get('/api/v2/diagnostics/smart_status');
      final data = response.data['data'] as List? ?? [];
      return data.whereType<Map<String, dynamic>>().map(SmartDrive.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> restartWireGuard() async {
    _ensureActive();
    await _client.post('/api/v2/status/service',
        data: await _serviceActionData('wireguard', 'restart'));
  }

  Future<void> sendWakeOnLan(String mac, {String? broadcast}) async {
    _ensureActive();
    await _client.post('/api/v2/services/wake_on_lan', data: {
      'mac': mac,
      if (broadcast != null) 'broadcast': broadcast,
    });
  }

  Future<List<int>> getConfigBackup() async {
    _ensureActive();
    return _client.getRawBytes('/api/v2/system/config');
  }

  Future<Map<String, dynamic>?> getPfBlockerStatus() async {
    _ensureActive();
    try {
      final response = await _client.get('/api/v2/status/pfblockerng');
      final data = response.data['data'];
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (_) {
      return null;
    }
  }

  Future<void> updatePfBlockerLists() async {
    _ensureActive();
    await _client.post('/api/v2/status/pfblockerng/update');
  }

  Future<void> setPfBlockerEnabled(bool enabled) async {
    _ensureActive();
    await _client.patch('/api/v2/status/pfblockerng',
        data: {'enable': enabled});
  }


  Future<bool> healthCheck() async {
    _ensureActive();
    try {
      await _client.get('/api/v2/status/system');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _serviceActionData(String serviceName, String action) async {
    _ensureActive();
    if (!_serviceIds.containsKey(serviceName)) await getServices();
    final id = _serviceIds[serviceName];
    return {if (id != null) 'id': id, 'name': serviceName, 'action': action};
  }

  Future<Map<String, dynamic>> runPing(
    String host, {
    int count = 4,
    String? interface,
  }) async {
    _ensureActive();
    final data = <String, dynamic>{'host': host, 'count': count};
    if (interface != null && interface.isNotEmpty) data['interface'] = interface;
    final response = await _client.post('/api/v2/diagnostics/ping', data: data);
    return response.data['data'] as Map<String, dynamic>? ?? response.data as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> runTraceroute(
    String host, {
    int maxHops = 30,
  }) async {
    _ensureActive();
    final response = await _client.post(
      '/api/v2/diagnostics/traceroute',
      data: {'host': host, 'max_hops': maxHops},
    );
    return response.data['data'] as Map<String, dynamic>? ?? response.data as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> runDnsLookup(
    String host, {
    String type = 'A',
  }) async {
    _ensureActive();
    final response = await _client.post(
      '/api/v2/diagnostics/dns_lookup',
      data: {'host': host, 'type': type},
    );
    return response.data['data'] as Map<String, dynamic>? ?? response.data as Map<String, dynamic>? ?? {};
  }

  Future<List<CaptivePortalSession>> getCaptivePortalSessions({String? zone}) async {
    _ensureActive();
    final params = <String, dynamic>{};
    if (zone != null && zone.isNotEmpty) params['zone'] = zone;
    final response = await _client.get('/api/v2/services/captiveportal/sessions', queryParameters: params.isNotEmpty ? params : null);
    final data = response.data['data'] as List? ?? [];
    return data.whereType<Map<String, dynamic>>().map(CaptivePortalSession.fromJson).toList();
  }

  Future<void> disconnectCaptivePortalSession({
    required String ipAddress,
    String? macAddress,
    String? zone,
  }) async {
    _ensureActive();
    final params = <String, dynamic>{'ip': ipAddress};
    if (macAddress != null && macAddress.isNotEmpty) params['mac'] = macAddress;
    if (zone != null && zone.isNotEmpty) params['zone'] = zone;
    await _client.delete('/api/v2/services/captiveportal/session', queryParameters: params);
  }

  Future<List<String>> generateCaptivePortalVouchers({
    required String zone,
    required int count,
    int minutes = 60,
  }) async {
    _ensureActive();
    final response = await _client.post(
      '/api/v2/services/captiveportal/vouchers',
      data: {'zone': zone, 'count': count, 'minutes': minutes},
    );
    final data = response.data['data'];
    if (data is List) {
      return data.map((v) {
        if (v is Map<String, dynamic>) {
          return (v['voucher'] ?? v['code'] ?? v['username'] ?? '').toString();
        }
        return v.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  Future<List<CaptivePortalVoucher>> getCaptivePortalVouchers({String? zone}) async {
    _ensureActive();
    final params = <String, dynamic>{};
    if (zone != null && zone.isNotEmpty) params['zone'] = zone;
    final response = await _client.get(
      '/api/v2/services/captiveportal/vouchers',
      queryParameters: params.isNotEmpty ? params : null,
    );
    final data = response.data['data'] as List? ?? [];
    return data.whereType<Map<String, dynamic>>().map(CaptivePortalVoucher.fromJson).toList();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('This pfSense session is no longer active.');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dashboardRequest = null;
    _firewallStateRequests.clear();
    _interfaceStatusRequest = null;
    _serviceIds.clear();
    _client.dispose();
  }
}

class _TopTalkerAgg {
  _TopTalkerAgg(this.ip);
  final String ip;
  String iface = '';
  int bytes = 0;
  int connections = 0;
}
