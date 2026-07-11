import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/dashboard_loader.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  group('partial dashboard loading', () {
    test('full success produces current combined dashboard data', () async {
      final client = _DashboardClient.success();
      addTearDown(client.dispose);

      final data = await loadDashboardData(client);

      expect(data.platform, 'pfSense Plus');
      expect(data.cpuUsage, 21);
      expect(data.interfaces.map((item) => item.name), ['wan', 'lan']);
      expect(data.gateways.single.name, 'WAN_DHCP');
      expect(data.systemStatus.isCurrent, isTrue);
      expect(data.interfaceStatus.isCurrent, isTrue);
      expect(data.gatewayStatus.isCurrent, isTrue);
      expect(data.hasAnySectionData, isTrue);
    });

    for (final failure in <String, _SingleFailureCase>{
      'gateway': _SingleFailureCase(
        path: '/api/v2/status/gateways',
        error: const ApiException('Gateway permission denied', 403),
      ),
      'interface': _SingleFailureCase(
        path: '/api/v2/status/interfaces',
        error: const ApiException('Interface endpoint unsupported', 404),
      ),
      'system': _SingleFailureCase(
        path: '/api/v2/status/system',
        error: const ApiException('System status unavailable', 503),
      ),
    }.entries) {
      test('${failure.key} failure preserves the other sections', () async {
        final client = _DashboardClient.success(
          failures: {failure.value.path: failure.value.error},
        );
        addTearDown(client.dispose);

        final data = await loadDashboardData(client);

        switch (failure.key) {
          case 'gateway':
            expect(data.systemStatus.isCurrent, isTrue);
            expect(data.interfaceStatus.isCurrent, isTrue);
            expect(data.gatewayStatus.isUnavailable, isTrue);
            expect(data.interfaces, hasLength(2));
            expect(data.gateways, isEmpty);
            expect(data.gatewayStatus.errorMessage, contains('403'));
          case 'interface':
            expect(data.systemStatus.isCurrent, isTrue);
            expect(data.gatewayStatus.isCurrent, isTrue);
            expect(data.interfaceStatus.isUnavailable, isTrue);
            expect(data.gateways, hasLength(1));
            expect(data.interfaces, isEmpty);
            expect(data.interfaceStatus.errorMessage, contains('unsupported'));
          case 'system':
            expect(data.systemStatus.isUnavailable, isTrue);
            expect(data.gatewayStatus.isCurrent, isTrue);
            expect(data.interfaceStatus.isCurrent, isTrue);
            expect(data.platform, 'pfSense dashboard');
            expect(data.gateways, hasLength(1));
            expect(data.interfaces, hasLength(2));
        }
      });
    }

    test('only system data can succeed without hiding its telemetry', () async {
      final client = _DashboardClient.success(
        failures: {
          '/api/v2/status/interfaces': const ApiException('No permission', 403),
          '/api/v2/status/gateways': const ApiException('Not installed', 404),
        },
      );
      addTearDown(client.dispose);

      final data = await loadDashboardData(client);

      expect(data.systemStatus.isCurrent, isTrue);
      expect(data.interfaceStatus.isUnavailable, isTrue);
      expect(data.gatewayStatus.isUnavailable, isTrue);
      expect(data.platform, 'pfSense Plus');
      expect(data.interfaces, isEmpty);
      expect(data.gateways, isEmpty);
    });

    test('only interface data can succeed without being discarded', () async {
      final client = _DashboardClient.success(
        failures: {
          '/api/v2/status/system': const ApiException('No permission', 403),
          '/api/v2/status/gateways': const ApiException('Not installed', 404),
        },
      );
      addTearDown(client.dispose);

      final data = await loadDashboardData(client);

      expect(data.systemStatus.isUnavailable, isTrue);
      expect(data.interfaceStatus.isCurrent, isTrue);
      expect(data.gatewayStatus.isUnavailable, isTrue);
      expect(data.interfaces, hasLength(2));
    });

    test('only gateway data can succeed without being discarded', () async {
      final client = _DashboardClient.success(
        failures: {
          '/api/v2/status/system': const ApiException('No permission', 403),
          '/api/v2/status/interfaces': const ApiException('Not installed', 404),
        },
      );
      addTearDown(client.dispose);

      final data = await loadDashboardData(client);

      expect(data.systemStatus.isUnavailable, isTrue);
      expect(data.interfaceStatus.isUnavailable, isTrue);
      expect(data.gatewayStatus.isCurrent, isTrue);
      expect(data.gateways, hasLength(1));
    });

    test('total failure returns explicit unavailable section states', () async {
      final client = _DashboardClient.success(
        failures: {
          '/api/v2/status/system': const ApiException('System denied', 403),
          '/api/v2/status/interfaces': const ApiException('Interfaces denied', 403),
          '/api/v2/status/gateways': const ApiException('Gateways denied', 403),
        },
      );
      addTearDown(client.dispose);

      final data = await loadDashboardData(client);

      expect(data.hasAnySectionData, isFalse);
      expect(data.systemStatus.isUnavailable, isTrue);
      expect(data.interfaceStatus.isUnavailable, isTrue);
      expect(data.gatewayStatus.isUnavailable, isTrue);
      expect(data.systemStatus.errorMessage, contains('System denied'));
      expect(data.interfaceStatus.errorMessage, contains('Interfaces denied'));
      expect(data.gatewayStatus.errorMessage, contains('Gateways denied'));
    });
  });

  test('service retains each last successful section after refresh failures',
      () async {
    final client = _DashboardClient.sequence(
      system: [
        _systemData(cpuUsage: 21),
        const ApiException('Transient system failure', 503),
      ],
      interfaces: [
        _interfaceData(),
        const ApiException('Transient interface failure', 503),
      ],
      gateways: [
        _gatewayData(),
        const ApiException('Transient gateway failure', 503),
      ],
    );
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final first = await service.getDashboard();
    final second = await service.getDashboard();

    expect(first.cpuUsage, 21);
    expect(first.interfaces, hasLength(2));
    expect(first.gateways, hasLength(1));

    expect(second.cpuUsage, 21);
    expect(second.interfaces, hasLength(2));
    expect(second.gateways, hasLength(1));
    expect(second.systemStatus.isStale, isTrue);
    expect(second.interfaceStatus.isStale, isTrue);
    expect(second.gatewayStatus.isStale, isTrue);
    expect(second.systemStatus.errorMessage, contains('Transient system'));
    expect(second.interfaceStatus.errorMessage, contains('Transient interface'));
    expect(second.gatewayStatus.errorMessage, contains('Transient gateway'));
  });
}

class _SingleFailureCase {
  const _SingleFailureCase({required this.path, required this.error});

  final String path;
  final Object error;
}

class _DashboardClient extends PfSenseApiClient {
  _DashboardClient._(this._responses)
      : super(
          PfSenseProfile(
            id: 'dashboard-partial-test',
            name: 'Dashboard partial test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  factory _DashboardClient.success({Map<String, Object> failures = const {}}) {
    return _DashboardClient._({
      '/api/v2/status/system': [
        failures['/api/v2/status/system'] ?? _systemData(),
      ],
      '/api/v2/status/interfaces': [
        failures['/api/v2/status/interfaces'] ?? _interfaceData(),
      ],
      '/api/v2/status/gateways': [
        failures['/api/v2/status/gateways'] ?? _gatewayData(),
      ],
    });
  }

  factory _DashboardClient.sequence({
    required List<Object> system,
    required List<Object> interfaces,
    required List<Object> gateways,
  }) {
    return _DashboardClient._({
      '/api/v2/status/system': [...system],
      '/api/v2/status/interfaces': [...interfaces],
      '/api/v2/status/gateways': [...gateways],
    });
  }

  final Map<String, List<Object>> _responses;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final queue = _responses[path];
    if (queue == null || queue.isEmpty) {
      throw StateError('No queued dashboard response for $path.');
    }
    final result = queue.removeAt(0);
    if (result is Error) throw result;
    if (result is Exception) throw result;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: result,
    );
  }
}

Map<String, dynamic> _systemData({double cpuUsage = 21}) {
  return {
    'data': {
      'cpu_usage': cpuUsage,
      'mem_usage': 37,
      'disk_usage': 42,
      'platform': 'pfSense Plus',
      'cpu_model': 'Test CPU',
      'cpu_count': 8,
      'uptime': '2 days',
      'cpu_load_avg': [0.1, 0.2, 0.3],
    },
  };
}

Map<String, dynamic> _interfaceData() {
  return {
    'data': [
      {
        'name': 'lan',
        'descr': 'LAN',
        'hwif': 'igc1',
        'status': 'up',
      },
      {
        'name': 'wan',
        'descr': 'WAN',
        'hwif': 'igc0',
        'status': 'up',
      },
    ],
  };
}

Map<String, dynamic> _gatewayData() {
  return {
    'data': [
      {
        'name': 'WAN_DHCP',
        'status': 'online',
        'delay': 8.4,
        'loss': 0,
      },
    ],
  };
}
