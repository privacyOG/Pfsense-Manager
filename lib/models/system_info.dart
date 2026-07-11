import 'system_repository.dart';

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
  final String? packageMirrorUrl;
  final List<SystemRepository> repositories;
  final String hostname;
  final String platform;
  final String uptime;
  final String buildTime;
  final String phpVersion;
  final String kernelVersion;
  final String? repositoryType;
  final DateTime fetchedAt;
  final String? lastUpdate;

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final root = _asMap(json['data']) ?? json;
    final flat = <String, dynamic>{};
    _flatten(root, flat);
    final repositories = _parseRepositories(root, flat);
    final repositoryType = _readNullable(
          flat,
          const ['repository_type', 'repo_type'],
        ) ??
        _firstReportedRepositoryName(repositories);

    return SystemInfo(
      systemType: _read(flat, const [
        'system_type',
        'product_name',
        'product',
        'distribution',
        'edition',
      ], 'pfSense'),
      version: _read(flat, const [
        'version',
        'firmware_version',
        'product_version',
        'base_version',
        'current_version',
        'installed_version',
        'version_full',
        'system_version',
      ], 'Unknown'),
      architecture: _read(flat, const [
        'architecture',
        'arch',
        'machine',
        'machine_arch',
        'cpu_arch',
        'platform_arch',
      ], 'Unknown'),
      gitCommit: _read(flat, const [
        'git_commit',
        'commit',
        'commit_hash',
        'revision',
        'build_commit',
      ], 'Unknown'),
      packageMirrorUrl: _readNullable(flat, const [
        'package_mirror_url',
        'package_mirror',
        'pkg_mirror',
        'mirror_url',
      ]),
      repositories: repositories,
      hostname: _read(flat, const [
        'hostname',
        'host',
        'system_hostname',
        'config_system_hostname',
      ], 'Unknown'),
      platform: _read(flat, const [
        'freebsd_version',
        'os_version',
        'platform_version',
        'uname',
        'platform',
      ], 'FreeBSD'),
      uptime: _readUptime(flat),
      buildTime: _read(
        flat,
        const ['buildtime', 'build_time', 'build_date'],
        '',
      ),
      phpVersion: _read(flat, const ['php_version'], 'Not reported'),
      kernelVersion: _read(flat, const [
        'kernel_version',
        'kernel',
        'kernel_release',
        'uname_r',
      ], 'Unknown'),
      repositoryType: repositoryType,
      lastUpdate: _readNullable(flat, const [
        'last_update',
        'last_updated',
        'update_timestamp',
        'updated_at',
      ]),
      fetchedAt: DateTime.now(),
    );
  }
}

void _flatten(
  Map<String, dynamic> source,
  Map<String, dynamic> target, [
  String prefix = '',
]) {
  for (final entry in source.entries) {
    final key = entry.key.toLowerCase();
    final path = prefix.isEmpty ? key : '${prefix}_$key';
    final value = entry.value;
    if (value is Map) {
      _flatten(Map<String, dynamic>.from(value), target, path);
    } else {
      target.putIfAbsent(key, () => value);
      target[path] = value;
    }
  }
}

List<SystemRepository> _parseRepositories(
  Map<String, dynamic> root,
  Map<String, dynamic> flat,
) {
  final raw = root['repositories'] ?? root['repos'] ?? root['repository_info'];
  final result = <SystemRepository>[];

  if (raw is List) {
    for (final value in raw) {
      final item = _repositoryFromValue(value);
      if (item != null && item.hasReportedData) result.add(item);
    }
  } else if (raw is Map) {
    for (final entry in raw.entries) {
      final value = entry.value;
      final item = value is Map
          ? _repositoryFromMap(<String, dynamic>{
              'name': entry.key.toString(),
              ...Map<String, dynamic>.from(value),
            })
          : _repositoryFromMap(<String, dynamic>{
              'name': entry.key.toString(),
              if (_reportedText(value) != null) 'url': _reportedText(value),
            });
      if (item.hasReportedData) result.add(item);
    }
  }

  if (result.isEmpty) {
    final explicit = _repositoryFromMap(<String, dynamic>{
      'name': _readNullable(flat, const [
        'repository_name',
        'repo_name',
      ]),
      'url': _readNullable(flat, const [
        'repository_url',
        'repo_url',
      ]),
      'priority': _readIntNullable(flat, const [
        'repository_priority',
        'repo_priority',
      ]),
      'enabled': _readBoolNullable(flat, const [
        'repository_enabled',
        'repo_enabled',
      ]),
    });
    if (explicit.hasReportedData) result.add(explicit);
  }

  final sourceOrder = <SystemRepository, int>{
    for (var index = 0; index < result.length; index++) result[index]: index,
  };
  result.sort((a, b) {
    final aPriority = a.priority;
    final bPriority = b.priority;
    if (aPriority == null && bPriority == null) {
      return sourceOrder[a]!.compareTo(sourceOrder[b]!);
    }
    if (aPriority == null) return 1;
    if (bPriority == null) return -1;
    final priorityCompare = aPriority.compareTo(bPriority);
    if (priorityCompare != 0) return priorityCompare;
    return sourceOrder[a]!.compareTo(sourceOrder[b]!);
  });
  return List.unmodifiable(result);
}

String? _firstReportedRepositoryName(List<SystemRepository> repositories) {
  for (final repository in repositories) {
    final name = repository.name;
    if (name != null && name.trim().isNotEmpty) return name;
  }
  return null;
}

SystemRepository? _repositoryFromValue(dynamic value) {
  final item = _asMap(value);
  if (item != null) return _repositoryFromMap(item);
  final text = _reportedText(value);
  return text == null ? null : SystemRepository(url: text);
}

SystemRepository _repositoryFromMap(Map<String, dynamic> data) {
  final flat = <String, dynamic>{};
  _flatten(data, flat);
  return SystemRepository(
    name: _readNullable(flat, const ['name', 'id', 'type']),
    url: _readNullable(flat, const ['url', 'mirror', 'repository_url']),
    priority: _readIntNullable(flat, const ['priority', 'order', 'weight']),
    enabled: _readBoolNullable(flat, const ['enabled', 'active']),
  );
}

String _readUptime(Map<String, dynamic> flat) {
  final text = _readNullable(
    flat,
    const ['uptime', 'system_uptime', 'uptime_text'],
  );
  if (text != null && !RegExp(r'^\d+$').hasMatch(text)) return text;
  final seconds = _readInt(
    flat,
    const ['uptime_seconds', 'uptime_sec'],
    int.tryParse(text ?? '') ?? -1,
  );
  if (seconds < 0) return 'Unknown';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final parts = <String>[];
  if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
  if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
  parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
  return parts.join(', ');
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

String _read(
  Map<String, dynamic> data,
  List<String> keys,
  String fallback,
) =>
    _readNullable(data, keys) ?? fallback;

String? _readNullable(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final text = _reportedText(data[key.toLowerCase()]);
    if (text != null) return text;
  }
  return null;
}

String? _reportedText(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

int _readInt(
  Map<String, dynamic> data,
  List<String> keys,
  int fallback,
) =>
    _readIntNullable(data, keys) ?? fallback;

int? _readIntNullable(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key.toLowerCase()];
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

bool? _readBoolNullable(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key.toLowerCase()];
    if (value is bool) return value;
    final text = value?.toString().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
  }
  return null;
}
