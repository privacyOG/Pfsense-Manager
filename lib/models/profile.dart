import '../utils/pfsense_endpoint.dart';

enum PfSenseAuthMode {
  apiKey,
  jwtPassword;

  String get storageValue => switch (this) {
        PfSenseAuthMode.apiKey => 'api_key',
        PfSenseAuthMode.jwtPassword => 'jwt_password',
      };

  static PfSenseAuthMode fromStorage(dynamic value) {
    return value?.toString() == 'jwt_password'
        ? PfSenseAuthMode.jwtPassword
        : PfSenseAuthMode.apiKey;
  }
}

/// Represents a pfSense instance profile stored locally.
class PfSenseProfile {
  final String id;
  String name;
  String host;
  int port;
  bool useHttps;
  bool allowSelfSignedCert;
  String username;
  PfSenseAuthMode authMode;
  String apiKey; // Encrypted at rest via flutter_secure_storage.
  String password; // Encrypted separately from the API key.

  PfSenseProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 443,
    this.useHttps = true,
    this.allowSelfSignedCert = false,
    required this.username,
    this.authMode = PfSenseAuthMode.apiKey,
    this.apiKey = '',
    this.password = '',
  }) {
    final endpoint = parsePfSenseEndpoint(
      host,
      fallbackPort: port,
      fallbackUseHttps: useHttps,
    );
    host = endpoint.host;
    port = endpoint.port;
    useHttps = endpoint.useHttps;
  }

  String get baseUrl => buildPfSenseBaseUrl(
        host: host,
        port: port,
        useHttps: useHttps,
      );

  bool get hasConfiguredCredential => switch (authMode) {
        PfSenseAuthMode.apiKey => apiKey.isNotEmpty,
        PfSenseAuthMode.jwtPassword => password.isNotEmpty,
      };

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'useHttps': useHttps,
      'allowSelfSignedCert': allowSelfSignedCert,
      'username': username,
      'authMode': authMode.storageValue,
      // Secrets are stored separately in secure storage and are never exported.
    };
  }

  factory PfSenseProfile.fromJson(Map<String, dynamic> json) {
    return PfSenseProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 443,
      useHttps: json['useHttps'] as bool? ?? true,
      allowSelfSignedCert: json['allowSelfSignedCert'] as bool? ?? false,
      username: json['username'] as String,
      authMode: PfSenseAuthMode.fromStorage(json['authMode']),
    );
  }

  PfSenseProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    bool? useHttps,
    bool? allowSelfSignedCert,
    String? username,
    PfSenseAuthMode? authMode,
    String? apiKey,
    String? password,
  }) {
    return PfSenseProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      allowSelfSignedCert: allowSelfSignedCert ?? this.allowSelfSignedCert,
      username: username ?? this.username,
      authMode: authMode ?? this.authMode,
      apiKey: apiKey ?? this.apiKey,
      password: password ?? this.password,
    );
  }
}
