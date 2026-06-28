/// System service model.
class SystemService {
  final int? id;
  final String name;
  final String displayName;
  final bool running;
  final String? pid;

  SystemService({
    this.id,
    required this.name,
    required this.displayName,
    required this.running,
    this.pid,
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
      running: _isRunningStatus(status),
      pid: _nullableString(json['pid']),
    );
  }

  factory SystemService.fromName(String name) {
    return SystemService(
      name: name,
      displayName: _getDisplayName(name),
      running: false,
    );
  }

  static String _getDisplayName(String name) {
    const displayNames = {
      'dnsmasq': 'DNS Resolver (Dnsmasq)',
      'unbound': 'DNS Resolver (Unbound)',
      'openvpn': 'OpenVPN Server',
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
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }
}
