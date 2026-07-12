import '../models/dashboard.dart';
import '../models/smart_drive.dart';
import 'pfrest_feature_registry.dart';

class HardwareHealthLoadResult {
  const HardwareHealthLoadResult({
    required this.health,
    required this.drives,
    this.smartError,
  });

  final DashboardData health;
  final List<SmartDrive> drives;
  final String? smartError;
}

Future<HardwareHealthLoadResult> loadHardwareHealthData({
  required Future<DashboardData> Function() loadHealth,
  required Future<List<SmartDrive>> Function() loadSmart,
  required PfRestFeatureDecision smartDecision,
}) async {
  final smartRequest = smartDecision.canAttempt
      ? _captureSmart(loadSmart)
      : Future.value(const _SmartResult(drives: []));

  final health = await loadHealth();
  final smart = await smartRequest;
  return HardwareHealthLoadResult(
    health: health,
    drives: smart.drives,
    smartError: smart.error,
  );
}

Future<_SmartResult> _captureSmart(
  Future<List<SmartDrive>> Function() load,
) async {
  try {
    return _SmartResult(drives: await load());
  } catch (error) {
    return _SmartResult(
      drives: const [],
      error: pfRestFeatureRequestErrorMessage(
        PfRestFeature.smartStatus,
        error,
      ),
    );
  }
}

class _SmartResult {
  const _SmartResult({required this.drives, this.error});

  final List<SmartDrive> drives;
  final String? error;
}
