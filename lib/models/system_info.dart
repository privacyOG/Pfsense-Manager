/// System information model.
class SystemInfo {
  final String version;
  final String platform;
  final String architecture;
  final String buildTime;
  final String phpVersion;
  final String kernelVersion;
  final String repositoryType;
  final String? lastUpdate;

  SystemInfo({
    required this.version,
    required this.platform,
    required this.architecture,
    required this.buildTime,
    required this.phpVersion,
    required this.kernelVersion,
    required this.repositoryType,
    this.lastUpdate,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return SystemInfo(
      version: data['version'] as String? ??
          data['platform'] as String? ??
          'Unknown',
      platform: data['platform'] as String? ?? 'pfSense',
      architecture: data['architecture'] as String? ??
          data['cpu_model'] as String? ??
          'Unknown',
      buildTime: data['buildtime'] as String? ?? data['uptime'] as String? ?? '',
      phpVersion: data['php_version'] as String? ?? 'N/A',
      kernelVersion: data['kernel_version'] as String? ??
          data['bios_version'] as String? ??
          'Unknown',
      repositoryType: data['repository_type'] as String? ??
          data['serial'] as String? ??
          'Unknown',
      lastUpdate: data['last_update'] as String?,
    );
  }
}
