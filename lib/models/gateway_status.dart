class GatewayStatus {
  GatewayStatus({required this.name, required this.status, required this.latency, this.packetLoss = 0, this.substatus, this.monitorIp, this.sourceIp});
  final String name;
  final String status;
  final String? substatus;
  final String? monitorIp;
  final String? sourceIp;
  final double latency;
  final double packetLoss;

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    return GatewayStatus(
      name: json['name']?.toString() ?? 'Unknown',
      status: json['status']?.toString() ?? 'unknown',
      substatus: json['substatus']?.toString(),
      monitorIp: json['monitorip']?.toString(),
      sourceIp: json['srcip']?.toString(),
      latency: parseGatewayNumber(json['delay'] ?? json['latency']),
      packetLoss: parseGatewayNumber(json['loss']),
    );
  }

  bool get online => status.toLowerCase().contains('online');
}

double parseGatewayNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
