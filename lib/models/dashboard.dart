/// System dashboard data from pfSense API.
class DashboardData {
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final double swapUsage;
  final double mbufUsage;
  final double? temperatureC;
  final int cpuCount;
  final String cpuModel;
  final String platform;
  final String uptime;
  final double loadAverage1;
  final double loadAverage5;
  final double loadAverage15;
  final List<GatewayStatus> gateways;
  final List<InterfaceStatus> interfaces;

  DashboardData({
    required this.cpuUsage,
    required this.memoryUsage,
    this.diskUsage = 0,
    this.swapUsage = 0,
    this.mbufUsage = 0,
    this.temperatureC,
    this.cpuCount = 0,
    this.cpuModel = 'Unknown CPU',
    this.platform = 'pfSense',
    required this.uptime,
    this.loadAverage1 = 0,
    this.loadAverage5 = 0,
    this.loadAverage15 = 0,
    this.gateways = const [],
    this.interfaces = const [],
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final loadAvg = json['cpu_load_avg'] as List? ?? const [];
    return DashboardData(
      cpuUsage: _parseDouble(json['cpu_usage']),
      memoryUsage: _parseDouble(json['mem_usage'] ?? json['memory_usage']),
      diskUsage: _parseDouble(json['disk_usage']),
      swapUsage: _parseDouble(json['swap_usage']),
      mbufUsage: _parseDouble(json['mbuf_usage']),
      temperatureC: _parseNullableDouble(json['temp_c']),
      cpuCount: _parseInt(json['cpu_count']),
      cpuModel: _string(json['cpu_model'], fallback: 'Unknown CPU'),
      platform: _string(json['platform'], fallback: 'pfSense'),
      uptime: _string(json['uptime'], fallback: 'Unknown'),
      loadAverage1: _parseDouble(loadAvg.isNotEmpty ? loadAvg[0] : null),
      loadAverage5: _parseDouble(loadAvg.length > 1 ? loadAvg[1] : null),
      loadAverage15: _parseDouble(loadAvg.length > 2 ? loadAvg[2] : null),
    );
  }

  DashboardData copyWith({
    List<GatewayStatus>? gateways,
    List<InterfaceStatus>? interfaces,
  }) {
    return DashboardData(
      cpuUsage: cpuUsage,
      memoryUsage: memoryUsage,
      diskUsage: diskUsage,
      swapUsage: swapUsage,
      mbufUsage: mbufUsage,
      temperatureC: temperatureC,
      cpuCount: cpuCount,
      cpuModel: cpuModel,
      platform: platform,
      uptime: uptime,
      loadAverage1: loadAverage1,
      loadAverage5: loadAverage5,
      loadAverage15: loadAverage15,
      gateways: gateways ?? this.gateways,
      interfaces: interfaces ?? this.interfaces,
    );
  }
}

class GatewayStatus {
  final String name;
  final String status;
  final String? substatus;
  final String? monitorIp;
  final String? sourceIp;
  final double latency;
  final double packetLoss;

  GatewayStatus({
    required this.name,
    required this.status,
    this.substatus,
    this.monitorIp,
    this.sourceIp,
    required this.latency,
    this.packetLoss = 0,
  });

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    return GatewayStatus(
      name: _string(json['name'], fallback: 'Unknown'),
      status: _string(json['status'], fallback: 'unknown'),
      substatus: _nullableString(json['substatus']),
      monitorIp: _nullableString(json['monitorip']),
      sourceIp: _nullableString(json['srcip']),
      latency: _parseDouble(json['delay'] ?? json['latency']),
      packetLoss: _parseDouble(json['loss']),
    );
  }

  bool get online => status.toLowerCase().contains('online');
}

class InterfaceStatus {
  final String name;
  final String description;
  final String hardwareInterface;
  final String status;
  final String? ipv4Address;
  final String? ipv6Address;
  final String? media;
  final String? gateway;
  final int bytesIn;
  final int bytesOut;
  final int packetsIn;
  final int packetsOut;
  final int errorsIn;
  final int errorsOut;
  final int collisions;

  InterfaceStatus({
    required this.name,
    required this.description,
    required this.hardwareInterface,
    required this.status,
    this.ipv4Address,
    this.ipv6Address,
    this.media,
    this.gateway,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.packetsIn = 0,
    this.packetsOut = 0,
    this.errorsIn = 0,
    this.errorsOut = 0,
    this.collisions = 0,
  });

  factory InterfaceStatus.fromJson(Map<String, dynamic> json) {
    final name = _string(json['name'], fallback: 'Interface');
    return InterfaceStatus(
      name: name,
      description: _string(json['descr'], fallback: name.toUpperCase()),
      hardwareInterface: _string(json['hwif']),
      status: _string(json['status'], fallback: 'unknown'),
      ipv4Address: _address(json['ipaddr'], json['subnet']),
      ipv6Address: _address(json['ipaddrv6'], json['subnetv6']),
      media: _nullableString(json['media']),
      gateway: _nullableString(json['gateway']),
      bytesIn: _parseInt(json['inbytes']),
      bytesOut: _parseInt(json['outbytes']),
      packetsIn: _parseInt(json['inpkts']),
      packetsOut: _parseInt(json['outpkts']),
      errorsIn: _parseInt(json['inerrs']),
      errorsOut: _parseInt(json['outerrs']),
      collisions: _parseInt(json['collisions']),
    );
  }

  bool get up => status.toLowerCase().contains('up');
}

String? _address(dynamic address, dynamic subnet) {
  final value = address?.toString();
  if (value == null || value.isEmpty) return null;
  final prefix = subnet?.toString();
  if (prefix == null || prefix.isEmpty) return value;
  return '$value/$prefix';
}

double _parseDouble(dynamic value) => _parseNullableDouble(value) ?? 0.0;

double? _parseNullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _parseInt(dynamic value) {
  if (value is num) return value.round();
  if (value is String) return double.tryParse(value)?.round() ?? 0;
  return 0;
}

String _string(dynamic value, {String fallback = ''}) {
  final text = value?.toString();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableString(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}
