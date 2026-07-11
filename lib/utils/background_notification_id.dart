import 'dart:convert';

import 'package:crypto/crypto.dart';

const _backgroundNotificationNamespace =
    'pfsense-manager/background-alert/v1';

/// Returns a stable positive Android notification identifier.
///
/// Identity components are trimmed, length-prefixed UTF-8 values. SHA-256 is
/// used so the result does not depend on the current Dart process. Only the
/// first 31 bits are exposed, keeping the value within Android's signed integer
/// range while avoiding disclosure of the profile or monitored item.
int backgroundNotificationId({
  required String profileId,
  required String monitoredItem,
  required String alertType,
}) {
  final identityBytes = <int>[
    ...utf8.encode(_backgroundNotificationNamespace),
    ..._lengthPrefixedUtf8(profileId.trim()),
    ..._lengthPrefixedUtf8(monitoredItem.trim()),
    ..._lengthPrefixedUtf8(alertType.trim()),
  ];
  final digest = sha256.convert(identityBytes).bytes;
  final value = ((digest[0] & 0x7f) << 24) |
      (digest[1] << 16) |
      (digest[2] << 8) |
      digest[3];
  return value == 0 ? 1 : value;
}

List<int> _lengthPrefixedUtf8(String value) {
  final bytes = utf8.encode(value);
  final length = bytes.length;
  return <int>[
    (length >> 24) & 0xff,
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
    ...bytes,
  ];
}
