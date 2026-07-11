import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/background_alert_diagnostics.dart';
import 'package:pfsense_manager/utils/api_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('records attempts and clears the last error only after success',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = BackgroundAlertDiagnosticsStore(prefs);
    final attempt = DateTime.utc(2026, 7, 11, 10, 0);
    final failureAt = DateTime.utc(2026, 7, 11, 10, 1);
    final success = DateTime.utc(2026, 7, 11, 10, 2);

    await store.recordAttempt(attempt);
    await store.recordFailure(
      const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.network,
        message: 'The firewall could not be reached from the current network.',
      ),
      failureAt,
    );

    final failed = store.read();
    expect(failed.lastAttempt?.toUtc(), attempt);
    expect(failed.lastSuccess, isNull);
    expect(failed.lastErrorAt?.toUtc(), failureAt);
    expect(
      failed.lastErrorCategory,
      BackgroundAlertFailureCategory.network,
    );
    expect(failed.lastAttemptSucceeded, isFalse);

    await store.recordSuccess(success);
    final recovered = store.read();
    expect(recovered.lastAttempt?.toUtc(), attempt);
    expect(recovered.lastSuccess?.toUtc(), success);
    expect(recovered.hasError, isFalse);
    expect(recovered.lastAttemptSucceeded, isTrue);
  });

  test('later failure retains the previous successful check timestamp',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = BackgroundAlertDiagnosticsStore(prefs);
    final success = DateTime.utc(2026, 7, 11, 9, 0);
    final attempt = DateTime.utc(2026, 7, 11, 10, 0);

    await store.recordSuccess(success);
    await store.recordAttempt(attempt);
    await store.recordFailure(
      const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.timeout,
        message: 'The firewall did not respond before the check timed out.',
      ),
      attempt,
    );

    final diagnostics = store.read();
    expect(diagnostics.lastSuccess?.toUtc(), success);
    expect(diagnostics.lastAttempt?.toUtc(), attempt);
    expect(diagnostics.hasError, isTrue);
    expect(diagnostics.lastAttemptSucceeded, isFalse);
  });

  test('classifies permission, TLS, timeout, network and pfREST failures', () {
    expect(
      classifyBackgroundAlertFailure(
        const ApiException('Forbidden response body', 403),
      ).category,
      BackgroundAlertFailureCategory.permission,
    );
    expect(
      classifyBackgroundAlertFailure(
        const ApiException(
          'Certificate includes firewall.example.test',
          null,
          false,
          false,
          true,
        ),
      ).category,
      BackgroundAlertFailureCategory.tls,
    );
    expect(
      classifyBackgroundAlertFailure(
        const ApiException('Timed out at 192.0.2.1', null, false, true),
      ).category,
      BackgroundAlertFailureCategory.timeout,
    );
    expect(
      classifyBackgroundAlertFailure(
        const ApiException('Cannot reach 192.0.2.1', null, true),
      ).category,
      BackgroundAlertFailureCategory.network,
    );

    final pfRest = classifyBackgroundAlertFailure(
      const ApiException('Sensitive response body', 500),
    );
    expect(pfRest.category, BackgroundAlertFailureCategory.pfRest);
    expect(pfRest.message, 'pfREST returned HTTP 500 during the background check.');
    expect(pfRest.message, isNot(contains('Sensitive response body')));
  });

  test('converts raw transport failures without retaining sensitive details', () {
    final error = DioException(
      requestOptions: RequestOptions(
        path: '/api/v2/status/system',
        baseUrl: 'https://private-firewall.example.test',
        headers: {'X-API-Key': 'private-key'},
      ),
      type: DioExceptionType.connectionError,
      message: 'Failed to reach private-firewall.example.test using private-key',
    );

    final failure = classifyBackgroundAlertFailure(error);

    expect(failure.category, BackgroundAlertFailureCategory.network);
    expect(failure.message, isNot(contains('private-firewall')));
    expect(failure.message, isNot(contains('private-key')));
  });

  test('generic failures use a fixed privacy-safe message', () {
    final failure = classifyBackgroundAlertFailure(
      StateError('api-key=secret host=private.example.test'),
    );

    expect(failure.category, BackgroundAlertFailureCategory.unexpected);
    expect(failure.message, isNot(contains('secret')));
    expect(failure.message, isNot(contains('private.example.test')));
  });
}
