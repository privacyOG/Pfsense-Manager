import '../models/dashboard.dart';
import '../utils/api_exception.dart';
import 'api_client.dart';

Future<DashboardData> loadDashboardData(
  PfSenseApiClient client, {
  DashboardData? previous,
}) async {
  final systemRequest = _captureDashboardSection(() async {
    final response = await client.get('/api/v2/status/system');
    final data = response.data['data'] as Map<String, dynamic>? ?? const {};
    return DashboardData.fromJson(data);
  });
  final interfaceRequest = _captureDashboardSection(() async {
    final response = await client.get('/api/v2/status/interfaces');
    final data = response.data['data'] as List? ?? const [];
    final interfaces = data
        .whereType<Map<String, dynamic>>()
        .map(InterfaceStatus.fromJson)
        .toList();
    return _sortInterfaceStatuses(interfaces);
  });
  final gatewayRequest = _captureDashboardSection(() async {
    final response = await client.get('/api/v2/status/gateways');
    final data = response.data['data'] as List? ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(GatewayStatus.fromJson)
        .toList();
  });

  final system = await systemRequest;
  final interfaces = await interfaceRequest;
  final gateways = await gatewayRequest;

  final systemStatus = _statusFor(
    system,
    previousHasData: previous?.systemStatus.hasData ?? false,
    sectionName: 'System status',
  );
  final interfaceStatus = _statusFor(
    interfaces,
    previousHasData: previous?.interfaceStatus.hasData ?? false,
    sectionName: 'Interface status',
  );
  final gatewayStatus = _statusFor(
    gateways,
    previousHasData: previous?.gatewayStatus.hasData ?? false,
    sectionName: 'Gateway status',
  );

  final base = system.value ??
      previous ??
      DashboardData.empty(
        systemStatus: systemStatus,
        gatewayStatus: gatewayStatus,
        interfaceStatus: interfaceStatus,
      );

  return base.copyWith(
    gateways: gateways.value ??
        (previous?.gatewayStatus.hasData == true
            ? previous!.gateways
            : const <GatewayStatus>[]),
    interfaces: interfaces.value ??
        (previous?.interfaceStatus.hasData == true
            ? previous!.interfaces
            : const <InterfaceStatus>[]),
    systemStatus: systemStatus,
    gatewayStatus: gatewayStatus,
    interfaceStatus: interfaceStatus,
  );
}

Future<_DashboardSectionResult<T>> _captureDashboardSection<T>(
  Future<T> Function() load,
) async {
  try {
    return _DashboardSectionResult<T>.success(await load());
  } catch (error) {
    return _DashboardSectionResult<T>.failure(error);
  }
}

DashboardSectionStatus _statusFor<T>(
  _DashboardSectionResult<T> result, {
  required bool previousHasData,
  required String sectionName,
}) {
  if (result.value != null) return const DashboardSectionStatus.current();
  final message = '$sectionName: ${_dashboardErrorMessage(result.error)}';
  return previousHasData
      ? DashboardSectionStatus.stale(message)
      : DashboardSectionStatus.unavailable(message);
}

String _dashboardErrorMessage(Object? error) {
  if (error is ApiException) return error.toString();
  if (error == null) return 'Unknown error.';
  final text = error.toString().trim();
  return text.isEmpty ? 'Unknown error.' : text;
}

List<InterfaceStatus> _sortInterfaceStatuses(
  List<InterfaceStatus> interfaces,
) {
  final sorted = [...interfaces];
  sorted.sort((a, b) {
    final aKey = _interfaceIdentity(a);
    final bKey = _interfaceIdentity(b);
    final rankCompare = _interfaceRank(aKey).compareTo(_interfaceRank(bKey));
    if (rankCompare != 0) return rankCompare;
    return aKey.compareTo(bKey);
  });
  return sorted;
}

String _interfaceIdentity(InterfaceStatus interface) {
  final name = interface.name.trim();
  if (name.isNotEmpty) return name.toLowerCase();
  final hardware = interface.hardwareInterface.trim();
  if (hardware.isNotEmpty) return hardware.toLowerCase();
  final description = interface.description.trim();
  return description.isEmpty ? 'unknown' : description.toLowerCase();
}

int _interfaceRank(String key) {
  if (key == 'wan') return 0;
  if (key == 'lan') return 1;
  if (key.startsWith('opt')) return 2;
  return 3;
}

class _DashboardSectionResult<T> {
  const _DashboardSectionResult.success(this.value) : error = null;
  const _DashboardSectionResult.failure(this.error) : value = null;

  final T? value;
  final Object? error;
}
