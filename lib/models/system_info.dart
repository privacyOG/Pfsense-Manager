import 'system_repository.dart';

/// Firmware, repository and runtime information reported by pfSense.
class SystemInfo {
  const SystemInfo({
    required this.systemType,
    required this.version,
    required this.architecture,
    required this.gitCommit,
    required this.packageMirrorUrl,
    required this.repositories,
    required this.hostname,
    required this.platform,
    required this.uptime,
    required this.buildTime,
    required this.phpVersion,
    required this.kernelVersion,
    required this.repositoryType,
    required this.fetchedAt,
    this.lastUpdate,
  });

  final String systemType;
  final String version;
  final String architecture;
  final String gitCommit;
  final String packageMirrorUrl;
  final List<SystemRepository> repositories;
  final String hostname;
  final String platform;
  final String uptime;
  final String buildTime;
  final String phpVersion;
  final String kernelVersion;
  final String repositoryType;
  final DateTime fetchedAt;
  final String? lastUpdate;

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final data = _asMap(json['data']) ?? json;
    final repositories = _parseRepositories(data);
    final repositoryType = _readString(data, const [
      'repository_type',
      'repo_type',
      'repository',
    ]);

    return SystemInfo(
      systemType: _readString(data, const [
        'system_type',
        'product_name',
        'product',
        'distribution',
      ], fallback: 'pfSense'),
      version: _readString(data, const [
        'version',
        'firmware_version',
        'product_version',
      ]),
      architecture: _readString(data, const [
        'architecture',
        'arch',
        'machine',
      ]),
      gitCommit: _readString(data, const [
        'git_commit',
        'commit',
        'commit_hash',
        'revision',
        'build_commit',
      ]),
      packageMirrorUrl: _readString(data, const [
        'package_mirror_url',
        'package_mirror',
        'pkg_mirror',
        'mirror_url',
      ], fallback: 'https://cloud.privacyx.co/'),
      repositories: repositories,
      hostname: _readString(data, const [
        'hostname',
        'host',
        'system_hostname',
      ]),
      platform: _readString(data, const [
        'os_version',
        'freebsd_version',
        'platform_version',
        'kernel_version',
        'platform',
      ]),
      uptime: _readString(data, const [
        'uptime',
        'system_uptime',
      ]),
      buildTime: _readString(data, const [
        'buildtime',
        'build_time',
        'build_date',
      ], fallback: ''),
      phpVersion: _readString(data, const [
        'php_version',
      ], fallback: 'Not reported'),
      kernelVersion: _readString(data, const [
        'kernel_version',
        'kernel',
        'uname',
      ]),
      repositoryType: repositoryType == 'Unknown' && repositories.isNotEmpty
          ? repositories.first.name
          : repositoryType,
      lastUpdate: _readNullableString(data, const [
        'last_update',
        'last_updated',
        'update_timestamp',
        'updated_at',
      ]),
      fetchedAt: DateTime.now(),
    );
  }
}

List<SystemRepository> _parseRepositories(Map<String, dynamic> data) {
  final raw = data['repositories'] ?? data['repos'] ?? data['repository_info'];
  final result = <SystemRepository>[];

  if (raw is List) {
    for (var index = 0; index < raw.length; index++) {
      final item = _asMap(raw[index]);
      if (item == null) continue;
      result.add(_repositoryFromMap(item, index));
    }
  } else if (raw is Map) {
    var index = 0;
    for (final entry in raw.entries) {
      final item = _asMap(entry.value) ?? <String, dynamic>{};
      result.add(_repositoryFromMap(
        <String, dynamic>{'name': entry.key.toString(), ...item},
        index,
      ));
      index++;
    }
  }

  if (result.isEmpty) {
    final type = _readNullableString(data, const [
      'repository_type',
      'repo_type',
      'repository',
    ]);
    final url = _readNullableString(data, const [
      'repository_url',
      'repo_url',
      'package_mirror_url',
      'package_mirror',
      'pkg_mirror',
    ]);
    if (type != null || url != null) {
      result.add(SystemRepository(
        name: type ?? 'Primary repository',
        url: url ?? 'https://cloud.privacyx.co/',
        priority: 1,
      ));
    }
  }

  result.sort((a, b) => a.priority.compareTo(b.priority));
  return List.unmodifiable(result);
}

SystemRepository _repositoryFromMap(Map<String, dynamic> data, int index) {
  return SystemRepository(
    name: _readString(data, const ['name', 'id', 'type'],
        fallback: 'Repository ${index + 1}'),
    url: _readString(data, const ['url', 'mirror', 'repository_url'],
        fallback: 'Not reported'),
    priority: _readInt(data, const ['priority', 'order', 'weight'],
        fallback: index + 1),
    enabled: _readBool(data, const ['enabled', 'active'], fallback: true),
  );
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

String _readString(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = 'Unknown',
}) {
  return _readNullableString(data, keys) ?? fallback;
}

String? _readNullableString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return null;
}

int _readInt(
  Map<String, dynamic> data,
  List<String> keys, {
  required int fallback,
}) {
  for (final key in keys) {
    final value = data[key];
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}

bool _readBool(
  Map<String, dynamic> data,
  List<String> keys, {
  required bool fallback,
}) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) return value;
    final text = value?.toString().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
  }
  return fallback;
}
