class OpenVpnServerStatus {
  const OpenVpnServerStatus({
    required this.name,
    required this.mode,
    required this.port,
    required this.vpnId,
    required this.connections,
  });

  final String name;
  final String mode;
  final String port;
  final String vpnId;
  final List<OpenVpnConnectionStatus> connections;

  factory OpenVpnServerStatus.fromJson(Map<String, dynamic> json) {
    return OpenVpnServerStatus(
      name: _text(json['name']),
      mode: _text(json['mode']),
      port: _text(json['port']),
      vpnId: _text(json['vpnid'] ?? json['vpn_id']),
      connections: _list(json['conns'] ?? json['connections'])
          .whereType<Map<String, dynamic>>()
          .map(OpenVpnConnectionStatus.fromJson)
          .toList(),
    );
  }

  String get displayName {
    for (final value in [name, vpnId, port]) {
      if (value.isNotEmpty) return value;
    }
    return 'OpenVPN';
  }
}

class OpenVpnConnectionStatus {
  const OpenVpnConnectionStatus({
    required this.commonName,
    required this.name,
    required this.remoteHost,
    required this.status,
  });

  final String commonName;
  final String name;
  final String remoteHost;
  final String status;

  factory OpenVpnConnectionStatus.fromJson(Map<String, dynamic> json) {
    return OpenVpnConnectionStatus(
      commonName: _text(json['common_name'] ?? json['commonName']),
      name: _text(json['name']),
      remoteHost: _text(json['remote_host']),
      status: _text(json['status'] ?? json['state']),
    );
  }

  String get displayName {
    for (final value in [commonName, name, remoteHost]) {
      if (value.isNotEmpty) return value;
    }
    return 'OpenVPN client';
  }
}

int openVpnConnectionCount(List<OpenVpnServerStatus> servers) {
  return servers.fold<int>(0, (count, server) => count + server.connections.length);
}

String _text(dynamic value) => value?.toString().trim() ?? '';

List<dynamic> _list(dynamic value) => value is List ? value : const [];
