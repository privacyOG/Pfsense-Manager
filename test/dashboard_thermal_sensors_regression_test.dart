import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';

void main() {
  test('parses four pfSense CPU sensors and ignores Fahrenheit helper values', () {
    final data = DashboardData.fromJson({
      'cpu_usage': 7,
      'mem_usage': 11,
      'uptime': '2 days',
      'thermal_sensors': {
        'dev.cpu.0.temperature': {'c': 35.7, 'f': 96.3},
        'dev.cpu.1.temperature': {'c': 35.7, 'f': 96.3},
        'dev.cpu.2.temperature': {'c': 35.7, 'f': 96.3},
        'dev.cpu.3.temperature': {'c': 35.7, 'f': 96.3},
      },
    });

    expect(data.thermalSensors.map((sensor) => sensor.name),
        ['CPU 0', 'CPU 1', 'CPU 2', 'CPU 3']);
    expect(data.thermalSensors.every((sensor) => sensor.temperatureC == 35.7),
        isTrue);
    expect(data.thermalSensors.any((sensor) => sensor.name == 'F'), isFalse);
    expect(data.temperatureC, 35.7);
  });
}
