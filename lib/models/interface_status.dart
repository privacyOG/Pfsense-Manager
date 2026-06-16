import 'dashboard_helpers.dart';

class InterfaceStatus {
  InterfaceStatus({
    required this.name,
    required this.description,
    required this.hardwareInterface,
    required this.status,
    this.ipv4Address,
    this.ipv6Address,
    this.media,
    this.gateway,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.packetsIn = 0,
    this.packetsOut = 0,
    this.errorsIn = 0,
    this.errorsOut = 0,
    this.collisions = 0,
  });

  final String name;
  final String description;
  final String hardwareInterface;
  final String status;
  final String? ipv4Address;
  final String? ipv6Address;
  final String? media;
  final String? gateway;
  final int bytesIn;
  final int bytesOut;
  final int packetsIn;
  final int packetsOut;
  final int errorsIn;
  final int errorsOut;
  final int collisions;

  factory InterfaceStatus.fromJson(Map<String, dynamic> json) {
    final name = textOr(json['name'], 'Interface');
    return InterfaceStatus(
      name: name,
      description: textOr(json['descr'], name.toUpperCase()),
      hardwareInterface: textOr(json['hwif'], ''),
      status: textOr(json['status'], 'unknown'),
      ipv4Address: addressWithPrefix(json['ipaddr'], json['subnet']),
      ipv6Address: addressWithPrefix(json['ipaddrv6'], json['subnetv6']),
      media: nullableText(json['media']),
      gateway: nullableText(json['gateway']),
      bytesIn: intOrZero(json['inbytes']),
      bytesOut: intOrZero(json['outbytes']),
      packetsIn: intOrZero(json['inpkts']),
      packetsOut: intOrZero(json['outpkts']),
      errorsIn: intOrZero(json['inerrs']),
      errorsOut: intOrZero(json['outerrs']),
      collisions: intOrZero(json['collisions']),
    );
  }

  bool get up => status.toLowerCase().contains('up');
}
