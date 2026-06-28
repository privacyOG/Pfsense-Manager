class DhcpLease {
  final String ipAddress;
  final String macAddress;
  final String hostname;
  final String interface;
  final String starts;
  final String ends;
  final String state;
  final String description;
  final bool active;
  final bool online;
  final bool expired;
  final bool staticMapping;

  DhcpLease({
    required this.ipAddress,
    required this.macAddress,
    required this.hostname,
    required this.interface,
    required this.starts,
    required this.ends,
    required this.state,
    this.description = '',
    required this.active,
    this.online = false,
    this.expired = false,
    required this.staticMapping,
  });

  factory DhcpLease.fromJson(Map<String, dynamic> json) {
    final activeStatus = _readText(json, ['active_status', 'activeStatus']);
    final onlineStatus = _readText(json, ['online_status', 'onlineStatus']);
    final fallbackState = _readText(json, ['state', 'status']);
    final leaseState = _leaseState(activeStatus, onlineStatus, fallbackState);

    return DhcpLease(
      ipAddress: _readText(json, ['ip', 'ip_address', 'address']),
      macAddress: _readText(json, ['mac', 'mac_address']),
      hostname: _readText(json, ['hostname', 'client_hostname']),
      interface: _readText(json, ['if', 'interface']),
      starts: _readText(json, ['starts', 'start']),
      ends: _readText(json, ['ends', 'end', 'expires']),
      state: leaseState,
      description: _readText(json, ['descr', 'description']),
      active: _isActive(activeStatus, onlineStatus, fallbackState, json['active']),
      online: _isOnline(onlineStatus, fallbackState),
      expired: _isExpired(activeStatus, onlineStatus, fallbackState),
      staticMapping: json['staticmap'] == true ||
          json['static'] == true ||
          json['type']?.toString().toLowerCase() == 'static',
    );
  }
}

String _readText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _leaseState(String activeStatus, String onlineStatus, String fallbackState) {
  final active = activeStatus.trim();
  final online = onlineStatus.trim();
  final fallback = fallbackState.trim();

  if (active.isNotEmpty && online.isNotEmpty) return '$active / $online';
  if (active.isNotEmpty) return active;
  if (online.isNotEmpty) return online;
  if (fallback.isNotEmpty) return fallback;
  return 'unknown';
}

bool _isActive(
  String activeStatus,
  String onlineStatus,
  String fallbackState,
  dynamic activeValue,
) {
  if (activeValue is bool) return activeValue;
  final active = activeStatus.toLowerCase();
  final online = onlineStatus.toLowerCase();
  final fallback = fallbackState.toLowerCase();
  if (_hasAny(active, ['expired', 'inactive', 'free', 'released'])) return false;
  if (_hasAny(active, ['active', 'static', 'reserved'])) return true;
  if (_hasAny(online, ['online', 'active'])) return true;
  return _hasAny(fallback, ['active', 'online', 'static', 'reserved']) &&
      !_hasAny(fallback, ['expired', 'inactive', 'free', 'released']);
}

bool _isOnline(String onlineStatus, String fallbackState) {
  final online = onlineStatus.toLowerCase();
  if (_hasAny(online, ['offline', 'inactive', 'down'])) return false;
  if (_hasAny(online, ['online', 'active', 'up'])) return true;
  final fallback = fallbackState.toLowerCase();
  return _hasAny(fallback, ['online', 'up']);
}

bool _isExpired(String activeStatus, String onlineStatus, String fallbackState) {
  final combined = '$activeStatus $onlineStatus $fallbackState'.toLowerCase();
  return _hasAny(combined, ['expired', 'inactive', 'free', 'released']);
}

bool _hasAny(String value, List<String> needles) {
  return needles.any(value.contains);
}
