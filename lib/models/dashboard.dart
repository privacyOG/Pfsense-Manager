import 'dashboard_helpers.dart';
import 'gateway_status.dart';
import 'interface_status.dart';
import 'thermal_sensor.dart';

export 'gateway_status.dart';
export 'interface_status.dart';
export 'thermal_sensor.dart';

enum DashboardSectionFreshness {
  current,
  stale,
  unavailable,
}

class DashboardSectionStatus {
  const DashboardSectionStatus._({
    required this.freshness,
    this.errorMessage,
  });

  const DashboardSectionStatus.current()
      : this._(freshness: DashboardSectionFreshness.current);

  const DashboardSectionStatus.stale(String errorMessage)
      : this._(
          freshness: DashboardSectionFreshness.stale,
          errorMessage: errorMessage,
        );

  const DashboardSectionStatus.unavailable(String errorMessage)
      : this._(
          freshness: DashboardSectionFreshness.unavailable,
          errorMessage: errorMessage,
        );

  final DashboardSectionFreshness freshness;
  final String? errorMessage;

  bool get hasData => freshness != DashboardSectionFreshness.unavailable;
  bool get isCurrent => freshness == DashboardSectionFreshness.current;
  bool get isStale => freshness == DashboardSectionFreshness.stale;
  bool get isUnavailable => freshness == DashboardSectionFreshness.unavailable;
}

class DashboardData {
  DashboardData({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.uptime,
    this.diskUsage = 0,
    this.swapUsage = 0,
    this.mbufUsage = 0,
    this.temperatureC,
    this.thermalSensors = const [],
    this.cpuCount = 0,
    this.cpuModel = 'Unknown CPU',
    this.platform = 'pfSense',
    this.loadAverage1 = 0,
    this.loadAverage5 = 0,
    this.loadAverage15 = 0,
    this.gateways = const [],
    this.interfaces = const [],
    this.systemStatus = const DashboardSectionStatus.current(),
    this.gatewayStatus = const DashboardSectionStatus.current(),
    this.interfaceStatus = const DashboardSectionStatus.current(),
  });

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
  final DashboardSectionStatus systemStatus;
  final DashboardSectionStatus gatewayStatus;
  final DashboardSectionStatus interfaceStatus;

  bool get hasAnySectionData =>
      systemStatus.hasData || gatewayStatus.hasData || interfaceStatus.hasData;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final load = json['cpu_load_avg'] as List? ?? const [];
    final sensors = parseThermalSensors(json);
    final hottest = sensors.isEmpty
        ? parseTemperature(json['temp_c'])
        : sensors
            .map((sensor) => sensor.temperatureC)
            .reduce((current, next) => current > next ? current : next);

    return DashboardData(
      cpuUsage: doubleOrZero(json['cpu_usage']),
      memoryUsage: doubleOrZero(json['mem_usage'] ?? json['memory_usage']),
      diskUsage: doubleOrZero(json['disk_usage']),
      swapUsage: doubleOrZero(json['swap_usage']),
      mbufUsage: doubleOrZero(json['mbuf_usage']),
      temperatureC: hottest,
      thermalSensors: sensors,
      cpuCount: intOrZero(json['cpu_count']),
      cpuModel: textOr(json['cpu_model'], 'Unknown CPU'),
      platform: textOr(json['platform'], 'pfSense'),
      uptime: textOr(json['uptime'], 'Unknown'),
      loadAverage1: doubleOrZero(load.isNotEmpty ? load[0] : null),
      loadAverage5: doubleOrZero(load.length > 1 ? load[1] : null),
      loadAverage15: doubleOrZero(load.length > 2 ? load[2] : null),
    );
  }

  factory DashboardData.empty({
    DashboardSectionStatus systemStatus =
        const DashboardSectionStatus.unavailable('System status unavailable.'),
    DashboardSectionStatus gatewayStatus =
        const DashboardSectionStatus.unavailable('Gateway status unavailable.'),
    DashboardSectionStatus interfaceStatus =
        const DashboardSectionStatus.unavailable('Interface status unavailable.'),
  }) {
    return DashboardData(
      cpuUsage: 0,
      memoryUsage: 0,
      uptime: 'Unavailable',
      cpuModel: 'System status unavailable',
      platform: 'pfSense dashboard',
      systemStatus: systemStatus,
      gatewayStatus: gatewayStatus,
      interfaceStatus: interfaceStatus,
    );
  }

  DashboardData copyWith({
    List<GatewayStatus>? gateways,
    List<InterfaceStatus>? interfaces,
    DashboardSectionStatus? systemStatus,
    DashboardSectionStatus? gatewayStatus,
    DashboardSectionStatus? interfaceStatus,
  }) {
    return DashboardData(
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
      systemStatus: systemStatus ?? this.systemStatus,
      gatewayStatus: gatewayStatus ?? this.gatewayStatus,
      interfaceStatus: interfaceStatus ?? this.interfaceStatus,
    );
  }
}
