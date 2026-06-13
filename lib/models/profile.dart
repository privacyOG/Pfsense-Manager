/// Represents a pfSense instance profile stored locally.
class PfSenseProfile {
  final String id;
  String name;
  String host;
  int port;
  bool useHttps;
  bool allowSelfSignedCert;
  String username;
  String apiKey; // Encrypted at rest via flutter_secure_storage

  PfSenseProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 443,
    this.useHttps = true,
    this.allowSelfSignedCert = false,
    required this.username,
    required this.apiKey,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'useHttps': useHttps,
      'allowSelfSignedCert': allowSelfSignedCert,
      'username': username,
      // apiKey is NOT serialized to JSON for security; it's stored separately
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
      apiKey: '', // Will be set from secure storage separately
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
    String? apiKey,
  }) {
    return PfSenseProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      allowSelfSignedCert: allowSelfSignedCert ?? this.allowSelfSignedCert,
      username: username ?? this.username,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}
