import '../utils/api_exception.dart';
import 'api_client.dart';

enum ConnectionFailureKind {
  authentication,
  permission,
  endpointUnavailable,
  timeout,
  tls,
  network,
  unexpected,
}

class ConnectionCapability {
  const ConnectionCapability({
    required this.name,
    required this.path,
    this.queryParameters,
  });

  final String name;
  final String path;
  final Map<String, dynamic>? queryParameters;
}

class ConnectionCapabilityResult {
  const ConnectionCapabilityResult.success(this.capability)
      : error = null;

  const ConnectionCapabilityResult.failure(this.capability, this.error);

  final ConnectionCapability capability;
  final Object? error;

  bool get succeeded => error == null;
  ApiException? get apiError => error is ApiException ? error as ApiException : null;

  String get compactFailure {
    final value = error;
    if (value is ApiException) {
      final code = value.statusCode;
      return code == null
          ? '${capability.name}: ${value.message}'
          : '${capability.name}: ${value.message} ($code)';
    }
    return '${capability.name}: ${value ?? 'Unknown error'}';
  }
}

class ConnectionCheckResult {
  const ConnectionCheckResult(this.capabilities);

  final List<ConnectionCapabilityResult> capabilities;

  List<ConnectionCapabilityResult> get successful =>
      capabilities.where((item) => item.succeeded).toList(growable: false);

  List<ConnectionCapabilityResult> get failed =>
      capabilities.where((item) => !item.succeeded).toList(growable: false);

  bool get connected => successful.isNotEmpty;
  bool get restricted => connected && failed.isNotEmpty;

  ConnectionFailureKind? get failureKind {
    if (connected) return null;
    final apiErrors = failed
        .map((item) => item.apiError)
        .whereType<ApiException>()
        .toList(growable: false);

    if (apiErrors.any((error) => error.isAuthenticationError)) {
      return ConnectionFailureKind.authentication;
    }
    if (apiErrors.any((error) => error.isTlsError)) {
      return ConnectionFailureKind.tls;
    }
    if (apiErrors.any((error) => error.isTimeout)) {
      return ConnectionFailureKind.timeout;
    }
    if (apiErrors.any((error) => error.isNetworkError)) {
      return ConnectionFailureKind.network;
    }
    if (apiErrors.any((error) => error.isPermissionError)) {
      return ConnectionFailureKind.permission;
    }
    if (apiErrors.isNotEmpty &&
        apiErrors.every((error) => error.isEndpointUnavailable)) {
      return ConnectionFailureKind.endpointUnavailable;
    }
    return ConnectionFailureKind.unexpected;
  }

  String get userMessage {
    if (connected) return successMessage;

    final checked = capabilities
        .map((item) => item.capability.name)
        .join(', ');
    final details = failed.map((item) => item.compactFailure).join('; ');

    final lead = switch (failureKind) {
      ConnectionFailureKind.authentication =>
        'Authentication failed (401). The firewall rejected the configured credential. Verify the profile username and API key or password.',
      ConnectionFailureKind.permission =>
        'Permission denied (403). The credential was accepted, but none of the connection-check capabilities are permitted. Grant read access to at least one checked capability.',
      ConnectionFailureKind.endpointUnavailable =>
        'No compatible pfREST connection-check endpoint was available. Verify that pfREST is enabled and compatible with this app version.',
      ConnectionFailureKind.timeout =>
        'Connection timed out. Verify routing, firewall rules, remote-access connectivity and firewall reachability.',
      ConnectionFailureKind.tls =>
        'TLS validation failed. Verify the endpoint hostname and certificate, or enable self-signed certificate support for this profile when appropriate.',
      ConnectionFailureKind.network =>
        'The firewall could not be reached. Verify the address, port, route and network connectivity.',
      ConnectionFailureKind.unexpected || null =>
        'The firewall did not provide a usable connection-check response.',
    };

    return '$lead\nChecked capabilities: $checked.\nDetails: $details';
  }

  String get successMessage {
    final accessible = successful
        .map((item) => item.capability.name)
        .join(', ');
    if (!restricted) {
      return 'Connection successful. Accessible capabilities: $accessible.';
    }
    final unavailable = failed.map((item) {
      final code = item.apiError?.statusCode;
      return code == null
          ? item.capability.name
          : '${item.capability.name} ($code)';
    }).join(', ');
    return 'Connection successful. Accessible capabilities: $accessible. Restricted or unavailable: $unavailable.';
  }
}

class PfSenseConnectionChecker {
  const PfSenseConnectionChecker(this.client);

  final PfSenseApiClient client;

  static const capabilities = <ConnectionCapability>[
    ConnectionCapability(
      name: 'System status',
      path: '/api/v2/status/system',
    ),
    ConnectionCapability(
      name: 'Interface status',
      path: '/api/v2/status/interfaces',
    ),
    ConnectionCapability(
      name: 'Gateway status',
      path: '/api/v2/status/gateways',
    ),
    ConnectionCapability(
      name: 'Firewall rules',
      path: '/api/v2/firewall/rules',
      queryParameters: {'limit': '1'},
    ),
    ConnectionCapability(
      name: 'Service status',
      path: '/api/v2/status/services',
    ),
  ];

  Future<ConnectionCheckResult> check() async {
    final results = await Future.wait(
      capabilities.map(_checkCapability),
    );
    return ConnectionCheckResult(results);
  }

  Future<ConnectionCapabilityResult> _checkCapability(
    ConnectionCapability capability,
  ) async {
    try {
      await client.get(
        capability.path,
        queryParameters: capability.queryParameters,
      );
      return ConnectionCapabilityResult.success(capability);
    } catch (error) {
      return ConnectionCapabilityResult.failure(capability, error);
    }
  }
}
