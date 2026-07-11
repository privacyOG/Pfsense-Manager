import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('dashboard requests remain deduplicated and refresh after success',
      () async {
    final client = _ControlledApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final first = service.getDashboard();
    final duplicate = service.getDashboard();

    expect(identical(first, duplicate), isTrue);
    expect(client.callCount('/api/v2/status/system'), 1);
    expect(client.callCount('/api/v2/status/interfaces'), 1);
    expect(client.callCount('/api/v2/status/gateways'), 1);

    client.completeNext('/api/v2/status/system', {'data': <String, dynamic>{}});
    client.completeNext('/api/v2/status/interfaces', {'data': <dynamic>[]});
    client.completeNext('/api/v2/status/gateways', {'data': <dynamic>[]});
    await first;

    final refresh = service.getDashboard();
    expect(identical(refresh, first), isFalse);
    expect(client.callCount('/api/v2/status/system'), 2);
    expect(client.callCount('/api/v2/status/interfaces'), 2);
    expect(client.callCount('/api/v2/status/gateways'), 2);

    client.completeNext('/api/v2/status/system', {'data': <String, dynamic>{}});
    client.completeNext('/api/v2/status/interfaces', {'data': <dynamic>[]});
    client.completeNext('/api/v2/status/gateways', {'data': <dynamic>[]});
    await refresh;
  });

  test('failed interface request is observed once and can be retried', () async {
    final client = _ControlledApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final unhandled = await _captureUnhandledErrors(() async {
      final first = service.getInterfaceStatuses();
      final duplicate = service.getInterfaceStatuses();

      expect(identical(first, duplicate), isTrue);
      expect(client.callCount('/api/v2/status/interfaces'), 1);

      client.failNext(
        '/api/v2/status/interfaces',
        StateError('interface request failed'),
      );
      await expectLater(
        first,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'interface request failed',
          ),
        ),
      );

      final retry = service.getInterfaceStatuses();
      expect(identical(retry, first), isFalse);
      expect(client.callCount('/api/v2/status/interfaces'), 2);
      client.completeNext('/api/v2/status/interfaces', {'data': <dynamic>[]});
      await retry;
    });

    expect(unhandled, isEmpty);
  });

  test('firewall state cache is keyed and clears after failure', () async {
    final client = _ControlledApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final unhandled = await _captureUnhandledErrors(() async {
      final first = service.getFirewallStates(limit: 200);
      final duplicate = service.getFirewallStates(limit: 200);
      final differentLimit = service.getFirewallStates(limit: 500);

      expect(identical(first, duplicate), isTrue);
      expect(identical(first, differentLimit), isFalse);
      expect(client.callCount('/api/v2/firewall/states'), 2);

      client.failNext(
        '/api/v2/firewall/states',
        const ApiException('state request failed'),
        queryValue: '200',
      );
      client.completeNext(
        '/api/v2/firewall/states',
        {'data': <dynamic>[]},
        queryValue: '500',
      );

      await expectLater(
        first,
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'state request failed',
          ),
        ),
      );
      await differentLimit;

      final retry = service.getFirewallStates(limit: 200);
      expect(client.callCount('/api/v2/firewall/states'), 3);
      client.completeNext(
        '/api/v2/firewall/states',
        {'data': <dynamic>[]},
        queryValue: '200',
      );
      await retry;
    });

    expect(unhandled, isEmpty);
  });

  test('disposing a session cancels pending work without cache mutation',
      () async {
    final client = _ControlledApiClient();
    final service = PfSenseService(client);

    final unhandled = await _captureUnhandledErrors(() async {
      final pending = service.getInterfaceStatuses();
      final duplicate = service.getInterfaceStatuses();
      expect(identical(pending, duplicate), isTrue);

      final failure = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Request cancelled.',
          ),
        ),
      );
      service.dispose();
      await failure;

      expect(
        service.getInterfaceStatuses,
        throwsA(isA<StateError>()),
      );
      expect(client.callCount('/api/v2/status/interfaces'), 1);
    });

    expect(unhandled, isEmpty);
  });
}

Future<List<Object>> _captureUnhandledErrors(
  Future<void> Function() body,
) async {
  final errors = <Object>[];
  final completed = Completer<void>();

  runZonedGuarded(
    () async {
      try {
        await body();
      } finally {
        if (!completed.isCompleted) completed.complete();
      }
    },
    (error, stackTrace) {
      errors.add(error);
    },
  );

  await completed.future;
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return errors;
}

class _ControlledApiClient extends PfSenseApiClient {
  _ControlledApiClient()
      : super(
          PfSenseProfile(
            id: 'request-cache-test',
            name: 'Request cache test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final List<_PendingGet> _pending = [];
  final Map<String, int> _calls = {};
  bool _closed = false;

  int callCount(String path) => _calls[path] ?? 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    _calls[path] = (_calls[path] ?? 0) + 1;
    final pending = _PendingGet(
      path: path,
      queryParameters: queryParameters,
      completer: Completer<Response<dynamic>>(),
    );
    _pending.add(pending);
    return pending.completer.future;
  }

  void completeNext(
    String path,
    dynamic data, {
    String? queryValue,
  }) {
    final pending = _take(path, queryValue: queryValue);
    pending.completer.complete(
      Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: data,
      ),
    );
  }

  void failNext(
    String path,
    Object error, {
    String? queryValue,
  }) {
    final pending = _take(path, queryValue: queryValue);
    pending.completer.completeError(error, StackTrace.current);
  }

  _PendingGet _take(String path, {String? queryValue}) {
    final index = _pending.indexWhere((pending) {
      if (pending.path != path) return false;
      if (queryValue == null) return true;
      return pending.queryParameters?['limit']?.toString() == queryValue;
    });
    if (index < 0) {
      throw StateError('No pending GET request for $path.');
    }
    return _pending.removeAt(index);
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const ApiException('Request cancelled.'),
          StackTrace.current,
        );
      }
    }
    _pending.clear();
    super.dispose();
  }
}

class _PendingGet {
  const _PendingGet({
    required this.path,
    required this.queryParameters,
    required this.completer,
  });

  final String path;
  final Map<String, dynamic>? queryParameters;
  final Completer<Response<dynamic>> completer;
}
