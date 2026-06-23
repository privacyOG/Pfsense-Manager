/// A single line from one of pfSense's system logs (system, DHCP, DNS, etc.).
///
/// pfSense exposes log lines either as plain syslog strings or as objects with
/// a `text`/`message` field. This model parses both shapes and best-effort
/// extracts the leading syslog timestamp, the originating process, and the
/// message body, always preserving the original [raw] line.
class SystemLogEntry {
  const SystemLogEntry({
    required this.raw,
    required this.timeLabel,
    required this.process,
    required this.message,
  });

  /// The unmodified log line as returned by pfSense.
  final String raw;

  /// The leading syslog timestamp (e.g. `Jun 23 14:05:01`), or an empty string
  /// when the line does not start with one.
  final String timeLabel;

  /// The process/daemon that emitted the line (e.g. `kernel`, `dhcpd`), or an
  /// empty string when it could not be determined.
  final String process;

  /// The message body. Falls back to [raw] when no syslog structure is found.
  final String message;

  // Jun 23 14:05:01 hostname process[pid]: message
  static final _syslogPattern = RegExp(
    r'^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{1,2}:\d{2}:\d{2})\s+\S+\s+([^:\[]+?)(?:\[\d+\])?:\s*(.*)$',
  );

  factory SystemLogEntry.fromJson(dynamic json) {
    if (json is String) return SystemLogEntry.fromText(json);
    if (json is Map) {
      final map = json.cast<String, dynamic>();
      final text = (map['text'] ??
              map['message'] ??
              map['msg'] ??
              map['line'] ??
              map['log'] ??
              '')
          .toString();

      final structuredTime =
          (map['time'] ?? map['timestamp'] ?? map['date'])?.toString();
      final structuredProcess =
          (map['process'] ?? map['prog'] ?? map['program'])?.toString();

      if (structuredTime != null && structuredTime.isNotEmpty) {
        return SystemLogEntry(
          raw: text.isNotEmpty ? text : structuredTime,
          timeLabel: structuredTime,
          process: structuredProcess ?? '',
          message: text,
        );
      }
      return SystemLogEntry.fromText(text);
    }
    return SystemLogEntry.fromText(json.toString());
  }

  factory SystemLogEntry.fromText(String text) {
    final trimmed = text.trimRight();
    final match = _syslogPattern.firstMatch(trimmed);
    if (match == null) {
      return SystemLogEntry(
        raw: trimmed,
        timeLabel: '',
        process: '',
        message: trimmed,
      );
    }
    return SystemLogEntry(
      raw: trimmed,
      timeLabel: match.group(1)?.trim() ?? '',
      process: match.group(2)?.trim() ?? '',
      message: match.group(3)?.trim() ?? '',
    );
  }
}
