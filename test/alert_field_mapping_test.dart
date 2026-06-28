import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/alert_service.dart';

void main() {
  group('alert field mappings', () {
    test('reads pfrest gateway packet loss from loss', () {
      expect(gatewayPacketLossPercent({'loss': '18.5'}), 18.5);
      expect(gatewayPacketLossPercent({'loss': '2.0%'}), 2.0);
    });

    test('keeps gateway packet loss compatibility fallbacks', () {
      expect(gatewayPacketLossPercent({'packet_loss': '7.5'}), 7.5);
      expect(gatewayPacketLossPercent({'packetloss': 4}), 4.0);
    });

    test('reads pfrest system temperature from temp_c', () {
      final readings = systemTemperatureReadings({'temp_c': 81.25});

      expect(readings, hasLength(1));
      expect(readings.first.name, 'CPU');
      expect(readings.first.celsius, 81.25);
    });

    test('keeps thermal sensor compatibility fallbacks', () {
      final readings = systemTemperatureReadings({
        'thermal_sensors': [
          {'name': 'Core 0', 'temperature_c': '74.5'},
          {'name': 'Core 1', 'temp': '75'},
        ],
      });

      expect(readings.map((item) => item.name), ['Core 0', 'Core 1']);
      expect(readings.map((item) => item.celsius), [74.5, 75.0]);
    });
  });
}
