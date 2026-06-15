import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/release_check_service.dart';

void main() {
  test('compares release versions safely', () {
    expect(ReleaseCheckService.isNewer('v1.7.1', '1.7.0'), isTrue);
    expect(ReleaseCheckService.isNewer('v1.7.0', '1.7.0'), isFalse);
    expect(ReleaseCheckService.isNewer('v1.8.0', '1.7.1+10'), isTrue);
    expect(ReleaseCheckService.isNewer('latest', '1.7.0'), isFalse);
  });
}
