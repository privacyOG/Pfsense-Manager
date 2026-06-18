class TopTalker {
  const TopTalker({
    required this.ipAddress,
    required this.bytes,
    required this.connections,
    this.hostname,
    this.interface = '',
  });

  final String ipAddress;
  final String? hostname;
  final String interface;
  final int bytes;
  final int connections;

  String get displayName => (hostname != null && hostname!.isNotEmpty) ? hostname! : ipAddress;
}
