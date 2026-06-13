class NetworkState {
  final String protocol;
  final String sourceIp;
  final String sourcePort;
  final String destinationIp;
  final String destinationPort;
  final String source;
  final String destination;
  final String interface;
  final String state;
  final int bytes;
  final int packets;
  final String age;
  final String expires;

  NetworkState({
    required this.protocol,
    required this.sourceIp,
    required this.sourcePort,
    required this.destinationIp,
    required this.destinationPort,
    required this.source,
    required this.destination,
    required this.interface,
    required this.state,
    required this.bytes,
    required this.packets,
    required this.age,
    required this.expires,
  });

  factory NetworkState.fromJson(Map<String, dynamic> json) {
    final sourceIp = (json['source'] ?? json['src'] ?? '').toString();
    final sourcePort = (json['source_port'] ?? json['sport'] ?? '').toString();
    final destinationIp =
        (json['destination'] ?? json['dst'] ?? '').toString();
    final destinationPort =
        (json['destination_port'] ?? json['dport'] ?? '').toString();
    return NetworkState(
      protocol: (json['protocol'] ?? json['proto'] ?? '').toString(),
      sourceIp: sourceIp,
      sourcePort: sourcePort,
      destinationIp: destinationIp,
      destinationPort: destinationPort,
      source: _endpoint(sourceIp, sourcePort),
      destination: _endpoint(destinationIp, destinationPort),
      interface: (json['interface'] ?? json['if'] ?? '').toString(),
      state: (json['state'] ?? json['tcp_state'] ?? '').toString(),
      bytes: _parseInt(json['bytes']),
      packets: _parseInt(json['packets']),
      age: (json['age'] ?? '').toString(),
      expires: (json['expires'] ?? json['expire'] ?? '').toString(),
    );
  }

  static String _endpoint(dynamic host, dynamic port) {
    final value = host?.toString() ?? '';
    final portValue = port?.toString() ?? '';
    if (portValue.isEmpty || portValue == '0') return value;
    return '$value:$portValue';
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
