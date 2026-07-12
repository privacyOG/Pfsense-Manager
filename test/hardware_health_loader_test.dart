import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/models/smart_drive.dart';
import 'package:pfsense_manager/services/hardware_health_loader.dart';
import 'package:pfsense_manager/services/pfrest_feature_registry.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('known unsupported SMART does not send a SMART request', () async {
    var healthCalls = 0;
    var smartCalls = 0;

    final result = await loadHardwareHealthData(
      loadHealth: () async {
        healthCalls++;
        return _health();
      },
      loadSmart: () async {
        smartCalls++;
        return const [];
      },
      smartDecision: _decision(PfRestFeatureAvailability.unsupported),
    );

    expect(healthCalls, 1);
    expect(smartCalls, 0);
    expect(result.health.memoryUsage, 42);
    expect(result.drives, isEmpty);
    expect(result.smartError, isNull);
  });

  test('SMART permission failure preserves standard hardware telemetry',
      () async {
    final result = await loadHardwareHealthData(
      loadHealth: () async => _health(),
      loadSmart: () async => throw const ApiException(
        'SMART read permission required',
        403,
      ),
      smartDecision: _decision(PfRestFeatureAvailability.available),
    );

    expect(result.health.temperatureC, 51);
    expect(result.health.memoryUsage, 42);
    expect(result.drives, isEmpty);
    expect(result.smartError, contains('Permission denied (403)'));
    expect(result.smartError, contains('SMART drive status'));
    expect(result.smartError, isNot(contains('not supported')));
  });

  test('limited capability state still attempts SMART for compatibility',
      () async {
    var smartCalls = 0;
    final drive = const SmartDrive(
      device: '/dev/ada0',
      description: 'Test drive',
      healthPassed: true,
    );

    final result = await loadHardwareHealthData(
      loadHealth: () async => _health(),
      loadSmart: () async {
        smartCalls++;
        return [drive];
      },
      smartDecision: _decision(PfRestFeatureAvailability.unknown),
    );

    expect(smartCalls, 1);
    expect(result.drives, [drive]);
    expect(result.smartError, isNull);
  });

  test('standard hardware failure remains a screen-level failure', () async {
    await expectLater(
      loadHardwareHealthData(
        loadHealth: () async => throw const ApiException(
          'System status unavailable',
          503,
        ),
        loadSmart: () async => const [],
        smartDecision: _decision(PfRestFeatureAvailability.available),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'System status unavailable',
        ),
      ),
    );
  });
}

DashboardData _health() {
  return DashboardData(
    cpuUsage: 12,
    memoryUsage: 42,
    swapUsage: 3,
    temperatureC: 51,
    uptime: '1 day',
  );
}

PfRestFeatureDecision _decision(PfRestFeatureAvailability availability) {
  final contract = pfRestFeatureContracts[PfRestFeature.smartStatus]!;
  return PfRestFeatureDecision(
    contract: contract,
    availability: availability,
    message: switch (availability) {
      PfRestFeatureAvailability.available => 'Available',
      PfRestFeatureAvailability.unsupported => 'Unsupported',
      PfRestFeatureAvailability.unknown => 'Unknown',
    },
  );
}
