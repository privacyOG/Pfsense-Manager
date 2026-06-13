class DhcpLease {
  final String ipAddress;
  final String macAddress;
  final String hostname;
  final String interface;
  final String starts;
  final String ends;
  final String state;
  final bool active;
  final bool staticMapping;

  DhcpLease({
    required this.ipAddress,
    required this.macAddress,
    required this.hostname,
    required this.interface,
    required this.starts,
    required this.ends,
    required this.state,
    required this.active,
    required this.staticMapping,
  });

  factory DhcpLease.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] ?? json['status'] ?? '').toString();
    return DhcpLease(
      ipAddress: (json['ip'] ?? json['ip_address'] ?? json['address'] ?? '')
          .toString(),
      macAddress: (json['mac'] ?? json['mac_address'] ?? '').toString(),
      hostname: (json['hostname'] ?? json['client_hostname'] ?? '').toString(),
      interface: (json['if'] ?? json['interface'] ?? '').toString(),
      starts: (json['starts'] ?? json['start'] ?? '').toString(),
      ends: (json['ends'] ?? json['end'] ?? json['expires'] ?? '').toString(),
      state: state.isEmpty ? 'unknown' : state,
      active: json['active'] == true ||
          state.toLowerCase().contains('active') ||
          state.toLowerCase().contains('online'),
      staticMapping: json['staticmap'] == true ||
          json['static'] == true ||
          json['type']?.toString().toLowerCase() == 'static',
    );
  }
}
