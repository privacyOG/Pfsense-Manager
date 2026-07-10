/// Firewall log entry parsed from a raw pfSense filterlog line.
class FirewallLog {
  final String id;
  final DateTime timestamp;
  final bool hasTimestamp;
  final bool isParsed;
  final String rawText;
  final String action; // PASS, BLOCK, REJECT, MATCH
  final String interface;
  final String reason;
  final String sourceIp;
  final int? sourcePort;
  final String destinationIp;
  final int? destinationPort;
  final String protocol;
  final int? length;
  final String? tcpFlags;

  FirewallLog({
    required this.id,
    required this.timestamp,
    this.hasTimestamp = true,
    this.isParsed = true,
    this.rawText = '',
    required this.action,
    required this.interface,
    required this.reason,
    required this.sourceIp,
    this.sourcePort,
    required this.destinationIp,
    this.destinationPort,
    required this.protocol,
    this.length,
    this.tcpFlags,
  });

  factory FirewallLog.fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString() ?? '';
    if (text.isNotEmpty) {
      return _fromText(text);
    }

    final parsedTimestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    return FirewallLog(
      id: json['id']?.toString() ?? _stableId(json.toString()),
      timestamp: parsedTimestamp ?? _unknownTimestamp,
      hasTimestamp: parsedTimestamp != null,
      isParsed: json.isNotEmpty,
      rawText: text,
      action: canonicalFirewallAction(json['action']?.toString() ?? 'UNKNOWN'),
      interface: json['interface']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      sourceIp: json['src_ip']?.toString() ?? '',
      sourcePort: _parseInt(json['src_port']),
      destinationIp: json['dst_ip']?.toString() ?? '',
      destinationPort: _parseInt(json['dst_port']),
      protocol: (json['proto']?.toString() ?? 'UNKNOWN').toUpperCase(),
      length: _parseInt(json['len']),
      tcpFlags: json['tcpflags']?.toString(),
    );
  }

  static FirewallLog _fromText(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return _unparsed(text);

    final marker = RegExp(
      r'filterlog(?:\[\d+\])?:\s*',
      caseSensitive: false,
    ).firstMatch(raw);
    final prefix = marker == null ? '' : raw.substring(0, marker.start).trim();
    final csv = marker == null ? raw : raw.substring(marker.end).trim();
    final parts = csv.split(',');
    String read(int index) => index < parts.length ? parts[index].trim() : '';

    if (parts.length < 9 || !_looksLikeFilterData(parts)) {
      return _unparsed(raw, timestamp: _parseTimestamp(prefix));
    }

    final timestamp = _parseTimestamp(prefix);
    final ipVersion = read(8);
    final isIpv6 = ipVersion == '6';
    final protocolIndex = isIpv6 ? 12 : 16;
    final lengthIndex = isIpv6 ? 14 : 17;
    final sourceIndex = isIpv6 ? 15 : 18;
    final destinationIndex = isIpv6 ? 16 : 19;
    final sourcePortIndex = isIpv6 ? 17 : 20;
    final destinationPortIndex = isIpv6 ? 18 : 21;
    final tcpFlagsIndex = isIpv6 ? 20 : 23;
    final protocol = read(protocolIndex).isEmpty
        ? 'UNKNOWN'
        : read(protocolIndex).toUpperCase();
    final supportsPorts = protocol == 'TCP' || protocol == 'UDP';

    return FirewallLog(
      id: _stableId(raw),
      timestamp: timestamp ?? _unknownTimestamp,
      hasTimestamp: timestamp != null,
      rawText: raw,
      action: canonicalFirewallAction(read(6)),
      interface: read(4),
      reason: read(5),
      sourceIp: read(sourceIndex),
      sourcePort: supportsPorts ? _parseInt(read(sourcePortIndex)) : null,
      destinationIp: read(destinationIndex),
      destinationPort:
          supportsPorts ? _parseInt(read(destinationPortIndex)) : null,
      protocol: protocol,
      length: _parseInt(read(lengthIndex)),
      tcpFlags: protocol == 'TCP' && read(tcpFlagsIndex).isNotEmpty
          ? read(tcpFlagsIndex)
          : null,
    );
  }

  static FirewallLog _unparsed(String text, {DateTime? timestamp}) {
    final raw = text.trim();
    return FirewallLog(
      id: _stableId(raw),
      timestamp: timestamp ?? _unknownTimestamp,
      hasTimestamp: timestamp != null,
      isParsed: false,
      rawText: raw,
      action: 'UNKNOWN',
      interface: '',
      reason: '',
      sourceIp: '',
      destinationIp: '',
      protocol: 'UNKNOWN',
    );
  }

  static bool _looksLikeFilterData(List<String> parts) {
    if (parts.length < 9) return false;
    final ipVersion = parts[8].trim();
    final action = parts[6].trim();
    return (ipVersion == '4' || ipVersion == '6') && action.isNotEmpty;
  }

  static DateTime? _parseTimestamp(String prefix) {
    if (prefix.isEmpty) return null;

    final isoMatch = RegExp(
      r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?',
    ).firstMatch(prefix);
    if (isoMatch != null) {
      final parsed = DateTime.tryParse(isoMatch.group(0)!);
      if (parsed != null) return parsed;
    }

    final bsdMatch = RegExp(
      r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\b',
    ).firstMatch(prefix);
    if (bsdMatch == null) return null;

    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final now = DateTime.now();
    var candidate = DateTime(
      now.year,
      months[bsdMatch.group(1)]!,
      int.parse(bsdMatch.group(2)!),
      int.parse(bsdMatch.group(3)!),
      int.parse(bsdMatch.group(4)!),
      int.parse(bsdMatch.group(5)!),
    );
    if (candidate.isAfter(now.add(const Duration(days: 2)))) {
      candidate = DateTime(
        now.year - 1,
        candidate.month,
        candidate.day,
        candidate.hour,
        candidate.minute,
        candidate.second,
      );
    }
    return candidate;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static String _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static final DateTime _unknownTimestamp =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  String get actionColorHex {
    switch (canonicalFirewallAction(action)) {
      case 'PASS':
        return '#4CAF50';
      case 'BLOCK':
        return '#F44336';
      case 'REJECT':
        return '#FF9800';
      default:
        return '#9E9E9E';
    }
  }

  String get formattedTime {
    if (!hasTimestamp) return '--:--:--';
    final local = timestamp.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get portInfo {
    if (sourcePort != null && destinationPort != null) {
      return '$sourcePort -> $destinationPort';
    }
    return '';
  }
}

String canonicalFirewallAction(String action) {
  final value = action.trim().toUpperCase();
  if (value.startsWith('PASS')) return 'PASS';
  if (value.startsWith('BLOCK')) return 'BLOCK';
  if (value.startsWith('REJECT')) return 'REJECT';
  if (value.startsWith('MATCH')) return 'MATCH';
  return value.isEmpty ? 'UNKNOWN' : value;
}

List<FirewallLog> filterFirewallLogs(
  Iterable<FirewallLog> logs, {
  String? action,
  String query = '',
  DateTime? since,
}) {
  final actionFilter = action == null || action.trim().isEmpty
      ? null
      : canonicalFirewallAction(action);
  final search = query.trim().toLowerCase();

  return logs.where((log) {
    if (actionFilter != null &&
        canonicalFirewallAction(log.action) != actionFilter) {
      return false;
    }
    if (since != null &&
        (!log.hasTimestamp || log.timestamp.isBefore(since))) {
      return false;
    }
    if (search.isEmpty) return true;
    return [
      log.sourceIp,
      log.destinationIp,
      log.interface,
      log.protocol,
      log.reason,
      log.portInfo,
      log.action,
      log.rawText,
    ].join(' ').toLowerCase().contains(search);
  }).toList();
}
