class CaptivePortalSession {
  const CaptivePortalSession({
    required this.ipAddress,
    required this.macAddress,
    this.username,
    this.sessionId,
    this.startTimestamp,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.zone = '',
  });

  final String ipAddress;
  final String macAddress;
  final String? username;
  final int? sessionId;
  final int? startTimestamp;
  final int bytesIn;
  final int bytesOut;
  final String zone;

  String get displayName => (username != null && username!.isNotEmpty)
      ? username!
      : ipAddress;

  Duration? get uptime {
    if (startTimestamp == null) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(startTimestamp! * 1000);
    return DateTime.now().difference(start);
  }

  factory CaptivePortalSession.fromJson(Map<String, dynamic> json) {
    return CaptivePortalSession(
      ipAddress: (json['ip'] ?? json['ip_address'] ?? json['clientip'] ?? '').toString(),
      macAddress: (json['mac'] ?? json['mac_address'] ?? '').toString(),
      username: _nullableString(json['username'] ?? json['user']),
      sessionId: _parseInt(json['session_id'] ?? json['id']),
      startTimestamp: _parseInt(json['start'] ?? json['login_timestamp']),
      bytesIn: _parseInt(json['bytes_in'] ?? json['bytesin'] ?? 0),
      bytesOut: _parseInt(json['bytes_out'] ?? json['bytesout'] ?? 0),
      zone: (json['zone'] ?? json['cpzone'] ?? '').toString(),
    );
  }

  static String? _nullableString(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
