import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/connection_check.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  group('connection capability checks', () {
    test('full success keeps existing profiles compatible', () async {
      final client = _ProbeClient.allSuccessful();
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.connected, isTrue);
      expect(result.restricted, isFalse);
      expect(result.successful, hasLength(5));
      expect(result.failed, isEmpty);
      expect(result.successMessage, contains('Connection successful'));
    });

    test('restricted profile connects when one permitted capability works',
        () async {
      final client = _ProbeClient({
        '/api/v2/status/system': const ApiException('Forbidden', 403),
        '/api/v2/status/interfaces': _success('/api/v2/status/interfaces'),
        '/api/v2/status/gateways': const ApiException('Forbidden', 403),
        '/api/v2/firewall/rules': const ApiException('Not found', 404),
        '/api/v2/status/services': const ApiException('Forbidden', 403),
      });
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.connected, isTrue);
      expect(result.restricted, isTrue);
      expect(
        result.successful.single.capability.name,
        'Interface status',
      );
      expect(result.failed, hasLength(4));
      expect(result.successMessage, contains('Interface status'));
      expect(result.successMessage, contains('System status (403)'));
      expect(
        result.failed.first.apiError?.isPermissionError,
        isTrue,
      );
    });

    test('401 remains an authentication failure', () async {
      final client = _ProbeClient.allFailed(
        const ApiException('Invalid credential', 401),
      );
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.connected, isFalse);
      expect(result.failureKind, ConnectionFailureKind.authentication);
      expect(result.userMessage, contains('Authentication failed (401)'));
      expect(result.userMessage, contains('System status'));
      expect(result.userMessage, contains('Invalid credential (401)'));
    });

    test('403 remains a distinct permission failure', () async {
      final client = _ProbeClient.allFailed(
        const ApiException('Read permission required', 403),
      );
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.connected, isFalse);
      expect(result.failureKind, ConnectionFailureKind.permission);
      expect(result.userMessage, contains('Permission denied (403)'));
      expect(result.userMessage, contains('Firewall rules'));
      expect(result.userMessage, contains('Read permission required (403)'));
    });

    test('404 reports endpoint compatibility instead of bad credentials',
        () async {
      final client = _ProbeClient.allFailed(
        const ApiException('Endpoint not found', 404),
      );
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.failureKind, ConnectionFailureKind.endpointUnavailable);
      expect(result.userMessage, contains('No compatible pfREST'));
      expect(result.userMessage, contains('Endpoint not found (404)'));
      expect(result.userMessage, isNot(contains('Authentication failed')));
    });

    test('timeout retains timeout remediation and endpoint details', () async {
      final client = _ProbeClient.allFailed(
        const ApiException(
          'Connection timed out. Check network and pfSense reachability.',
          null,
          false,
          true,
        ),
      );
      addTearDown(client.dispose);

      final result = await PfSenseConnectionChecker(client).check();

      expect(result.failureKind, ConnectionFailureKind.timeout);
      expect(result.userMessage, contains('Connection timed out'));
      expect(result.userMessage, contains('Gateway status'));
    });

    test('TLS and network failures remain distinguishable', () async {
      final tlsClient = _ProbeClient.allFailed(
        const ApiException(
          'TLS certificate validation failed.',
          null,
          false,
          false,
          true,
        ),
      );
      final networkClient = _ProbeClient.allFailed(
        const ApiException('Network error.', null, true),
      );
      addTearDown(tlsClient.dispose);
      addTearDown(networkClient.dispose);

      final tls = await PfSenseConnectionChecker(tlsClient).check();
      final network = await PfSenseConnectionChecker(networkClient).check();

      expect(tls.failureKind, ConnectionFailureKind.tls);
      expect(tls.userMessage, contains('TLS validation failed'));
      expect(network.failureKind, ConnectionFailureKind.network);
      expect(network.userMessage, contains('could not be reached'));
    });
  });

  group('API exception classification', () {
    test('separates authentication and permission status codes', () {
      const authentication = ApiException('Unauthorized', 401);
      const permission = ApiException('Forbidden', 403);

      expect(authentication.isAuthenticationError, isTrue);
      expect(authentication.isPermissionError, isFalse);
      expect(permission.isAuthenticationError, isFalse);
      expect(permission.isPermissionError, isTrue);
      expect(authentication.isAuthError, isTrue);
      expect(permission.isAuthError, isTrue);
    });

    test('classifies certificate failures as TLS errors', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/v2/status/system'),
        type: DioExceptionType.badCertificate,
        message: 'Certificate rejected',
      );

      final exception = ApiException.fromDio(error);

      expect(exception.isTlsError, isTrue);
      expect(exception.isNetworkError, isFalse);
      expect(exception.message, contains('certificate validation failed'));
    });
  });
}

class _ProbeClient extends PfSenseApiClient {
  _ProbeClient(this._results)
      : super(
          PfSenseProfile(
            id: 'connection-check-test',
            name: 'Connection check test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  factory _ProbeClient.allSuccessful() {
    return _ProbeClient({
      for (final capability in PfSenseConnectionChecker.capabilities)
        capability.path: _success(capability.path),
    });
  }

  factory _ProbeClient.allFailed(Object error) {
    return _ProbeClient({
      for (final capability in PfSenseConnectionChecker.capabilities)
        capability.path: error,
    });
  }

  final Map<String, Object> _results;
  bool closed = false;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final result = _results[path];
    if (result == null) throw StateError('No probe result for $path.');
    if (result is Error) throw result;
    if (result is Exception) throw result;
    return result as Response<dynamic>;
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    super.dispose();
  }
}

Response<dynamic> _success(String path) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: <String, dynamic>{'data': <dynamic>[]},
  );
}
