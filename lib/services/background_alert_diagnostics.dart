import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_exception.dart';

enum BackgroundAlertFailureCategory {
  notificationPermission,
  notification,
  scheduling,
  configuration,
  authentication,
  permission,
  tls,
  timeout,
  network,
  pfRest,
  unexpected,
}

extension BackgroundAlertFailureCategoryLabel
    on BackgroundAlertFailureCategory {
  String get label => switch (this) {
        BackgroundAlertFailureCategory.notificationPermission =>
          'Notification permission',
        BackgroundAlertFailureCategory.notification =>
          'Notification delivery',
        BackgroundAlertFailureCategory.scheduling => 'Background scheduling',
        BackgroundAlertFailureCategory.configuration => 'Configuration',
        BackgroundAlertFailureCategory.authentication => 'Authentication',
        BackgroundAlertFailureCategory.permission => 'API permission',
        BackgroundAlertFailureCategory.tls => 'TLS certificate',
        BackgroundAlertFailureCategory.timeout => 'Connection timeout',
        BackgroundAlertFailureCategory.network => 'Network connection',
        BackgroundAlertFailureCategory.pfRest => 'pfREST response',
        BackgroundAlertFailureCategory.unexpected => 'Unexpected failure',
      };
}

class BackgroundAlertFailure {
  const BackgroundAlertFailure({
    required this.category,
    required this.message,
  });

  final BackgroundAlertFailureCategory category;
  final String message;
}

class BackgroundAlertDiagnostics {
  const BackgroundAlertDiagnostics({
    this.lastAttempt,
    this.lastSuccess,
    this.lastErrorAt,
    this.lastErrorCategory,
    this.lastErrorMessage,
  });

  final DateTime? lastAttempt;
  final DateTime? lastSuccess;
  final DateTime? lastErrorAt;
  final BackgroundAlertFailureCategory? lastErrorCategory;
  final String? lastErrorMessage;

  bool get hasAttempted => lastAttempt != null;
  bool get hasSucceeded => lastSuccess != null;
  bool get hasError =>
      lastErrorAt != null &&
      lastErrorCategory != null &&
      lastErrorMessage != null;

  bool get lastAttemptSucceeded {
    final attempt = lastAttempt;
    final success = lastSuccess;
    if (attempt == null || success == null) return false;
    return !success.isBefore(attempt);
  }
}

class BackgroundAlertDiagnosticsStore {
  BackgroundAlertDiagnosticsStore(this.preferences);

  final SharedPreferences preferences;

  static const _lastAttemptKey = 'alert.diagnostics.lastAttempt';
  static const _lastSuccessKey = 'alert.diagnostics.lastSuccess';
  static const _lastErrorAtKey = 'alert.diagnostics.lastErrorAt';
  static const _lastErrorCategoryKey = 'alert.diagnostics.lastErrorCategory';
  static const _lastErrorMessageKey = 'alert.diagnostics.lastErrorMessage';

  BackgroundAlertDiagnostics read() {
    return BackgroundAlertDiagnostics(
      lastAttempt: _readDate(_lastAttemptKey),
      lastSuccess: _readDate(_lastSuccessKey),
      lastErrorAt: _readDate(_lastErrorAtKey),
      lastErrorCategory: _readCategory(
        preferences.getString(_lastErrorCategoryKey),
      ),
      lastErrorMessage: preferences.getString(_lastErrorMessageKey),
    );
  }

  Future<void> recordAttempt(DateTime timestamp) async {
    await preferences.setString(
      _lastAttemptKey,
      timestamp.toUtc().toIso8601String(),
    );
  }

  Future<void> recordSuccess(DateTime timestamp) async {
    await preferences.setString(
      _lastSuccessKey,
      timestamp.toUtc().toIso8601String(),
    );
    await preferences.remove(_lastErrorAtKey);
    await preferences.remove(_lastErrorCategoryKey);
    await preferences.remove(_lastErrorMessageKey);
  }

  Future<void> recordFailure(
    BackgroundAlertFailure failure,
    DateTime timestamp,
  ) async {
    await preferences.setString(
      _lastErrorAtKey,
      timestamp.toUtc().toIso8601String(),
    );
    await preferences.setString(
      _lastErrorCategoryKey,
      failure.category.name,
    );
    await preferences.setString(_lastErrorMessageKey, failure.message);
  }

  Future<void> clear() async {
    await preferences.remove(_lastAttemptKey);
    await preferences.remove(_lastSuccessKey);
    await preferences.remove(_lastErrorAtKey);
    await preferences.remove(_lastErrorCategoryKey);
    await preferences.remove(_lastErrorMessageKey);
  }

  DateTime? _readDate(String key) {
    final value = preferences.getString(key);
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  BackgroundAlertFailureCategory? _readCategory(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final category in BackgroundAlertFailureCategory.values) {
      if (category.name == value) return category;
    }
    return BackgroundAlertFailureCategory.unexpected;
  }
}

class BackgroundAlertNotificationPermissionException implements Exception {
  const BackgroundAlertNotificationPermissionException();
}

class BackgroundAlertNotificationException implements Exception {
  const BackgroundAlertNotificationException();
}

class BackgroundAlertSchedulingException implements Exception {
  const BackgroundAlertSchedulingException();
}

class BackgroundAlertConfigurationException implements Exception {
  const BackgroundAlertConfigurationException();
}

BackgroundAlertFailure classifyBackgroundAlertFailure(Object error) {
  if (error is BackgroundAlertNotificationPermissionException) {
    return const BackgroundAlertFailure(
      category: BackgroundAlertFailureCategory.notificationPermission,
      message:
          'Notification permission is disabled. Allow notifications for pfSense Manager in Android settings.',
    );
  }
  if (error is BackgroundAlertNotificationException) {
    return const BackgroundAlertFailure(
      category: BackgroundAlertFailureCategory.notification,
      message:
          'A local alert could not be delivered. Check notification permission and battery restrictions.',
    );
  }
  if (error is BackgroundAlertSchedulingException) {
    return const BackgroundAlertFailure(
      category: BackgroundAlertFailureCategory.scheduling,
      message:
          'Android could not schedule the periodic check. Review battery optimization and background activity settings.',
    );
  }
  if (error is BackgroundAlertConfigurationException) {
    return const BackgroundAlertFailure(
      category: BackgroundAlertFailureCategory.configuration,
      message:
          'The selected firewall profile or its credential is unavailable. Open Profiles and save the connection details again.',
    );
  }

  final apiError = error is DioException ? ApiException.fromDio(error) : error;
  if (apiError is ApiException) {
    if (apiError.isAuthenticationError) {
      return const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.authentication,
        message:
            'The firewall rejected the saved credential. Verify the selected profile authentication details.',
      );
    }
    if (apiError.isPermissionError) {
      return const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.permission,
        message:
            'The saved credential cannot read the status endpoints required by background alerts.',
      );
    }
    if (apiError.isTlsError) {
      return const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.tls,
        message:
            'TLS validation failed. Verify the profile hostname and certificate settings.',
      );
    }
    if (apiError.isTimeout) {
      return const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.timeout,
        message:
            'The firewall did not respond before the background check timed out.',
      );
    }
    if (apiError.isNetworkError) {
      return const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.network,
        message:
            'The firewall could not be reached from the current network.',
      );
    }
    final status = apiError.statusCode;
    return BackgroundAlertFailure(
      category: BackgroundAlertFailureCategory.pfRest,
      message: status == null
          ? 'pfREST returned an unusable response during the background check.'
          : 'pfREST returned HTTP $status during the background check.',
    );
  }

  return const BackgroundAlertFailure(
    category: BackgroundAlertFailureCategory.unexpected,
    message:
        'The background check failed unexpectedly. Open this screen after the next scheduled check for an updated status.',
  );
}
