import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';

void main() {
  group('DashboardData thermal sensor parsing', () {
    test('parses named CPU sensor objects', () {
      final data = DashboardData.fromJson({
        'cpu_usage': 12,
        'mem_usage': 34,
        'uptime': '1 day',
        'thermal_sensors': [
          {'name': 'CPU Package', 'temperature': '54.5 C'},
          {'name': 'Core 0', 'temp_c': 49},
          {'name': 'Core 1', 'temp_c': '51.2'},
        ],
      });

      expect(data.thermalSensors, hasLength(3));
      expect(
        data.thermalSensors.map((sensor) => sensor.name),
        containsAll(['CPU Package', 'Core 0', 'Core 1']),
      );
      expect(data.temperatureC, 54.5);
    });

    test('parses temperature maps and orders numbered cores', () {
      final data = DashboardData.fromJson({
        'cpu_usage': 12,
        'mem_usage': 34,
        'uptime': '1 day',
        'cpu_temperatures': {
          'core_2': '53 C',
          'core_0': '48 C',
          'core_1': '50 C',
        },
      });

      expect(
        data.thermalSensors.map((sensor) => sensor.name).toList(),
        ['Core 0', 'Core 1', 'Core 2'],
      );
      expect(data.temperatureC, 53);
    });

    test('keeps legacy single temperature support', () {
      final data = DashboardData.fromJson({
        'cpu_usage': 12,
        'mem_usage': 34,
        'uptime': '1 day',
        'temp_c': '46.8 °C',
      });

      expect(data.thermalSensors, hasLength(1));
      expect(data.thermalSensors.single.temperatureC, 46.8);
      expect(data.temperatureC, 46.8);
    });

    test('ignores invalid non-temperature values', () {
      final data = DashboardData.fromJson({
        'cpu_usage': 12,
        'mem_usage': 34,
        'uptime': '1 day',
        'thermal_sensors': {
          'fan_rpm': 2200,
          'core_0': 44,
          'core_1': 250,
        },
      });

      expect(data.thermalSensors, hasLength(1));
      expect(data.thermalSensors.single.name, 'Core 0');
      expect(data.thermalSensors.single.temperatureC, 44);
    });
  });
}
