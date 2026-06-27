class TopTalker {
  const TopTalker({
    required this.ipAddress,
    required this.bytes,
    required this.connections,
    this.hostname,
    this.interface = '',
    this.bytesPerSecond = 0,
  });

  final String ipAddress;
  final String? hostname;
  final String interface;
  final int bytes;
  final int connections;
  final double bytesPerSecond;

  int get rateBytesPerSecond => bytesPerSecond.round();

  String get displayName =>
      (hostname != null && hostname!.isNotEmpty) ? hostname! : ipAddress;
}
