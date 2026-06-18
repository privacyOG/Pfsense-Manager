class WireGuardPeer {
  const WireGuardPeer({
    required this.publicKey,
    required this.description,
    required this.allowedIps,
    this.endpoint,
    this.lastHandshake,
    this.enabled = true,
  });

  final String publicKey;
  final String description;
  final List<String> allowedIps;
  final String? endpoint;
  final DateTime? lastHandshake;
  final bool enabled;

  factory WireGuardPeer.fromJson(Map<String, dynamic> json) {
    DateTime? handshake;
    final hs = json['last_handshake'];
    if (hs is int && hs > 0) {
      handshake = DateTime.fromMillisecondsSinceEpoch(hs * 1000);
    } else if (hs is String && hs.isNotEmpty && hs != '0') {
      handshake = DateTime.tryParse(hs);
    }
    return WireGuardPeer(
      publicKey: json['publickey']?.toString() ?? json['public_key']?.toString() ?? '',
      description: json['descr']?.toString() ?? json['description']?.toString() ?? '',
      allowedIps: _parseAllowedIps(json),
      endpoint: json['endpoint']?.toString().isNotEmpty == true ? json['endpoint'].toString() : null,
      lastHandshake: handshake,
      enabled: json['enabled'] != false && json['disabled'] != true,
    );
  }

  static List<String> _parseAllowedIps(Map<String, dynamic> json) {
    final raw = json['allowed_ips'] ?? json['allowedips'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) return raw.split(',').map((s) => s.trim()).toList();
    return [];
  }
}

class WireGuardTunnel {
  const WireGuardTunnel({
    required this.name,
    required this.description,
    required this.enabled,
    required this.publicKey,
    required this.listenPort,
    required this.peers,
  });

  final String name;
  final String description;
  final bool enabled;
  final String publicKey;
  final String listenPort;
  final List<WireGuardPeer> peers;

  factory WireGuardTunnel.fromJson(Map<String, dynamic> json) {
    final peersRaw = json['peers'] as List? ?? [];
    return WireGuardTunnel(
      name: json['name']?.toString() ?? json['tun']?.toString() ?? '',
      description: json['descr']?.toString() ?? json['description']?.toString() ?? '',
      enabled: json['enabled'] != false && json['disabled'] != true,
      publicKey: json['publickey']?.toString() ?? json['public_key']?.toString() ?? '',
      listenPort: json['listenport']?.toString() ?? json['listen_port']?.toString() ?? '',
      peers: peersRaw.whereType<Map<String, dynamic>>().map(WireGuardPeer.fromJson).toList(),
    );
  }
}
