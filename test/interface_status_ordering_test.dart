import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';

void main() {
  test('InterfaceStatus keeps pfrest interface identity fields available', () {
    final interface = InterfaceStatus.fromJson({
      'name': 'opt2',
      'descr': 'LAN2',
      'hwif': 'igb2',
      'status': 'up',
    });

    expect(interface.name, 'opt2');
    expect(interface.description, 'LAN2');
    expect(interface.hardwareInterface, 'igb2');
    expect(interface.up, isTrue);
  });
}
