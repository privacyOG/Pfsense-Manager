/// Firewall log entry model.
class FirewallLog {
  final String id;
  final DateTime timestamp;
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
    final text = json['text'] as String?;
    if (text != null && text.isNotEmpty) {
      return _fromText(text);
    }

    return FirewallLog(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      action: json['action'] as String? ?? 'UNKNOWN',
      interface: json['interface'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      sourceIp: json['src_ip'] as String? ?? '',
      sourcePort: _parseInt(json['src_port']),
      destinationIp: json['dst_ip'] as String? ?? '',
      destinationPort: _parseInt(json['dst_port']),
      protocol: json['proto'] as String? ?? 'TCP',
      length: _parseInt(json['len']),
      tcpFlags: json['tcpflags'] as String?,
    );
  }

  static FirewallLog _fromText(String text) {
    final parts = text.split(',');
    String read(int index) => index < parts.length ? parts[index].trim() : '';
    final timestamp = DateTime.tryParse(read(0)) ?? DateTime.now();
    final action = read(6).isNotEmpty ? read(6).toUpperCase() : 'UNKNOWN';
    final interface = read(4);
    final reason = read(5);
    final protocol = read(16).isNotEmpty ? read(16).toUpperCase() : 'UNKNOWN';

    return FirewallLog(
      id: text.hashCode.toString(),
      timestamp: timestamp,
      action: action,
      interface: interface,
      reason: reason,
      sourceIp: read(18),
      sourcePort: _parseInt(read(20)),
      destinationIp: read(19),
      destinationPort: _parseInt(read(21)),
      protocol: protocol,
      length: _parseInt(read(7)),
      tcpFlags: read(23).isEmpty ? null : read(23),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  String get actionColorHex {
    switch (action.toUpperCase()) {
      case 'PASS':
        return '#4CAF50';
      case 'BLOCK':
      case 'BLOCK6':
        return '#F44336';
      case 'REJECT':
      case 'REJECT6':
        return '#FF9800';
      default:
        return '#9E9E9E';
    }
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get portInfo {
    if (sourcePort != null && destinationPort != null) {
      return '$sourcePort -> $destinationPort';
    }
    return '';
  }
}
