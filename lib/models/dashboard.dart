class DashboardData {
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final double swapUsage;
  final double mbufUsage;
  final double? temperatureC;
  final List<ThermalSensor> thermalSensors;
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
    this.thermalSensors = const [],
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
    final load = json['cpu_load_avg'] as List? ?? const [];
    final sensors = parseThermalSensors(json);
    final hottest = sensors.isEmpty
        ? _temperature(json['temp_c'])
        : sensors.map((e) => e.temperatureC).reduce((a, b) => a > b ? a : b);
    return DashboardData(
      cpuUsage: _double(json['cpu_usage']),
      memoryUsage: _double(json['mem_usage'] ?? json['memory_usage']),
      diskUsage: _double(json['disk_usage']),
      swapUsage: _double(json['swap_usage']),
      mbufUsage: _double(json['mbuf_usage']),
      temperatureC: hottest,
      thermalSensors: sensors,
      cpuCount: _int(json['cpu_count']),
      cpuModel: _text(json['cpu_model'], 'Unknown CPU'),
      platform: _text(json['platform'], 'pfSense'),
      uptime: _text(json['uptime'], 'Unknown'),
      loadAverage1: _double(load.isNotEmpty ? load[0] : null),
      loadAverage5: _double(load.length > 1 ? load[1] : null),
      loadAverage15: _double(load.length > 2 ? load[2] : null),
    );
  }

  DashboardData copyWith({List<GatewayStatus>? gateways, List<InterfaceStatus>? interfaces}) =>
      DashboardData(
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        diskUsage: diskUsage,
        swapUsage: swapUsage,
        mbufUsage: mbufUsage,
        temperatureC: temperatureC,
        thermalSensors: thermalSensors,
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

class ThermalSensor {
  const ThermalSensor({required this.name, required this.temperatureC});
  final String name;
  final double temperatureC;
}

class GatewayStatus {
  GatewayStatus({
    required this.name,
    required this.status,
    this.substatus,
    this.monitorIp,
    this.sourceIp,
    required this.latency,
    this.packetLoss = 0,
  });
  final String name;
  final String status;
  final String? substatus;
  final String? monitorIp;
  final String? sourceIp;
  final double latency;
  final double packetLoss;

  factory GatewayStatus.fromJson(Map<String, dynamic> json) => GatewayStatus(
        name: _text(json['name'], 'Unknown'),
        status: _text(json['status'], 'unknown'),
        substatus: _nullable(json['substatus']),
        monitorIp: _nullable(json['monitorip']),
        sourceIp: _nullable(json['srcip']),
        latency: _double(json['delay'] ?? json['latency']),
        packetLoss: _double(json['loss']),
      );

  bool get online => status.toLowerCase().contains('online');
}

class InterfaceStatus {
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

  factory InterfaceStatus.fromJson(Map<String, dynamic> json) {
    final name = _text(json['name'], 'Interface');
    return InterfaceStatus(
      name: name,
      description: _text(json['descr'], name.toUpperCase()),
      hardwareInterface: _text(json['hwif'], ''),
      status: _text(json['status'], 'unknown'),
      ipv4Address: _address(json['ipaddr'], json['subnet']),
      ipv6Address: _address(json['ipaddrv6'], json['subnetv6']),
      media: _nullable(json['media']),
      gateway: _nullable(json['gateway']),
      bytesIn: _int(json['inbytes']),
      bytesOut: _int(json['outbytes']),
      packetsIn: _int(json['inpkts']),
      packetsOut: _int(json['outpkts']),
      errorsIn: _int(json['inerrs']),
      errorsOut: _int(json['outerrs']),
      collisions: _int(json['collisions']),
    );
  }

  bool get up => status.toLowerCase().contains('up');
}

List<ThermalSensor> parseThermalSensors(Map<String, dynamic> json) {
  final values = <String, double>{};

  void add(String path, dynamic raw) {
    final value = _temperature(raw);
    if (value == null || value < -30 || value > 125) return;
    final name = _sensorName(path);
    if (name == null) return;
    values[name] = value;
  }

  void walk(dynamic node, String path) {
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      for (final entry in map.entries) {
        final child = path.isEmpty ? entry.key : '$path.${entry.key}';
        final key = entry.key.toLowerCase();
        if (_unitKey(key)) continue;
        if (entry.value is num || entry.value is String) {
          if (_thermalPath(child)) add(child, entry.value);
        } else {
          walk(entry.value, child);
        }
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        walk(node[i], '$path.${i + 1}');
      }
    }
  }

  walk(json, '');
  if (values.isEmpty) add('System sensor', json['temp_c']);

  final result = values.entries
      .map((e) => ThermalSensor(name: e.key, temperatureC: e.value))
      .toList();
  result.sort((a, b) => _natural(a.name, b.name));
  return result;
}

bool _thermalPath(String path) {
  final lower = path.toLowerCase();
  return lower.contains('temperature') || lower.contains('thermal') ||
      lower.endsWith('temp_c') || lower.endsWith('.temp');
}

bool _unitKey(String key) => const {
      'c', 'f', 'celsius', 'fahrenheit', 'degc', 'degf',
      'value_c', 'value_f', 'temperature_c', 'temperature_f'
    }.contains(key);

String? _sensorName(String path) {
  final cpu = RegExp(r'cpu[._ ]*(\d+)', caseSensitive: false).firstMatch(path);
  if (cpu != null) return 'CPU ${cpu.group(1)}';
  final lower = path.toLowerCase();
  if (lower == 'temp_c' || lower.contains('system')) return 'System sensor';
  if (lower.endsWith('.f') || lower.endsWith('.fahrenheit')) return null;
  return path
      .replaceAll(RegExp(r'[_\-.]+'), ' ')
      .replaceAll(RegExp(r'\b(temp|temperature|thermal|celsius|degc)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _natural(String a, String b) {
  final aa = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '');
  final bb = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '');
  if (aa != null && bb != null && aa != bb) return aa.compareTo(bb);
  return a.compareTo(b);
}

String? _address(dynamic address, dynamic subnet) {
  final value = _nullable(address);
  if (value == null) return null;
  final prefix = _nullable(subnet);
  return prefix == null ? value : '$value/$prefix';
}

double _double(dynamic value) => _nullableDouble(value) ?? 0;
double? _nullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double? _temperature(dynamic value) {
  if (value is num) return value.toDouble();
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value?.toString() ?? '');
  return match == null ? null : double.tryParse(match.group(0)!);
}

int _int(dynamic value) {
  if (value is num) return value.round();
  return double.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

String _text(dynamic value, String fallback) => _nullable(value) ?? fallback;
String? _nullable(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}
