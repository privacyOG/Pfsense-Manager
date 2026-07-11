/// System service model.
class SystemService {
  final int? id;
  final String name;
  final String displayName;
  final bool enabled;
  final bool running;
  final String? pid;
  final String? mode;
  final String? vpnId;

  SystemService({
    this.id,
    required this.name,
    required this.displayName,
    this.enabled = true,
    required this.running,
    this.pid,
    this.mode,
    this.vpnId,
  });

  factory SystemService.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    return SystemService(
      id: _parseInt(json['id']),
      name: _string(json['name']),
      displayName:
          _nullableString(json['description']) ??
          _nullableString(json['display_name']) ??
          _nullableString(json['name']) ??
          '',
      enabled: _parseBool(json['enabled'], fallback: true),
      running: _isRunningStatus(status),
      pid: _nullableString(json['pid']),
      mode: _nullableString(json['mode']),
      vpnId: _nullableString(json['vpnid'] ?? json['vpn_id']),
    );
  }

  factory SystemService.fromName(String name) {
    return SystemService(
      name: name,
      displayName: _getDisplayName(name),
      running: false,
    );
  }

  bool get isOpenVpn => name.trim().toLowerCase() == 'openvpn';

  String get instanceKey => id == null ? name : '$name:$id';

  String get instanceDetails {
    final details = <String>[
      if (mode != null && mode!.isNotEmpty) mode!,
      if (vpnId != null && vpnId!.isNotEmpty) 'VPN ID $vpnId',
      if (id != null) 'Service #$id',
    ];
    return details.join(' · ');
  }

  String get instanceLabel {
    if (instanceDetails.isEmpty) return displayName;
    return '$displayName ($instanceDetails)';
  }

  static String _getDisplayName(String name) {
    const displayNames = {
      'dnsmasq': 'DNS Resolver (Dnsmasq)',
      'unbound': 'DNS Resolver (Unbound)',
      'openvpn': 'OpenVPN',
      'openssh': 'SSH Daemon',
      'dhcpd': 'DHCP Server',
      'ntpd': 'NTP Client',
      'snmpd': 'SNMP Daemon',
      'collectd': 'CollectD',
      'dynDNS': 'Dynamic DNS',
      'ipsec': 'IPSec',
      'radius': 'RADIUS Accounting',
      'webgui': 'Web Interface',
    };
    return displayNames[name] ?? name;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static bool _parseBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    final normalized = _string(value).trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return fallback;
  }

  static bool _isRunningStatus(dynamic value) {
    if (value is bool) return value;
    final status = _string(value).toLowerCase().trim();
    return status == 'running' ||
        status == 'started' ||
        status == 'active' ||
        status == 'up';
  }

  static String _string(dynamic value) => value?.toString() ?? '';

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
