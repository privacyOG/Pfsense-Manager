import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/utils/background_notification_id.dart';

void main() {
  test('same identity always returns the documented golden value', () {
    final values = List<int>.generate(
      100,
      (_) => backgroundNotificationId(
        profileId: 'firewall-1',
        monitoredItem: 'WAN_DHCP',
        alertType: 'down',
      ),
    );

    expect(values.toSet(), {556429145});
  });

  test('profile, monitored item and alert type are independent dimensions', () {
    final baseline = backgroundNotificationId(
      profileId: 'firewall-1',
      monitoredItem: 'WAN_DHCP',
      alertType: 'down',
    );
    final otherProfile = backgroundNotificationId(
      profileId: 'firewall-2',
      monitoredItem: 'WAN_DHCP',
      alertType: 'down',
    );
    final otherItem = backgroundNotificationId(
      profileId: 'firewall-1',
      monitoredItem: 'LAN_GATEWAY',
      alertType: 'down',
    );
    final otherType = backgroundNotificationId(
      profileId: 'firewall-1',
      monitoredItem: 'WAN_DHCP',
      alertType: 'loss',
    );

    expect(baseline, 556429145);
    expect(otherProfile, 596460538);
    expect(otherType, 756815216);
    expect({baseline, otherProfile, otherItem, otherType}, hasLength(4));
  });

  test('trims incidental surrounding whitespace before hashing', () {
    final canonical = backgroundNotificationId(
      profileId: 'firewall-1',
      monitoredItem: 'WAN_DHCP',
      alertType: 'down',
    );
    final padded = backgroundNotificationId(
      profileId: '  firewall-1  ',
      monitoredItem: '  WAN_DHCP  ',
      alertType: '  down  ',
    );

    expect(padded, canonical);
  });

  test('handles Unicode identity values deterministically', () {
    final id = backgroundNotificationId(
      profileId: 'ملف-١',
      monitoredItem: 'بوابة رئيسية',
      alertType: 'انقطاع',
    );

    expect(id, 574072188);
  });

  test('always returns a positive signed 31-bit integer', () {
    for (var index = 0; index < 2000; index++) {
      final id = backgroundNotificationId(
        profileId: 'profile-$index',
        monitoredItem: 'item-${index * 17}',
        alertType: 'type-${index % 7}',
      );
      expect(id, inInclusiveRange(1, 0x7fffffff));
    }
  });

  test('representative cross-profile alert identities do not collide', () {
    final ids = <int>{};
    for (var profile = 0; profile < 50; profile++) {
      for (var item = 0; item < 20; item++) {
        for (final type in const ['down', 'loss', 'temp']) {
          ids.add(
            backgroundNotificationId(
              profileId: 'profile-$profile',
              monitoredItem: 'item-$item',
              alertType: type,
            ),
          );
        }
      }
    }

    expect(ids, hasLength(3000));
  });

  test('length prefixes prevent component-boundary ambiguity', () {
    final first = backgroundNotificationId(
      profileId: 'ab',
      monitoredItem: 'c',
      alertType: 'down',
    );
    final second = backgroundNotificationId(
      profileId: 'a',
      monitoredItem: 'bc',
      alertType: 'down',
    );

    expect(first, isNot(second));
  });
}
