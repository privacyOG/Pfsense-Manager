import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';

void main() {
  test('pfSense API client does not follow redirects', () {
    final client = PfSenseApiClient(
      PfSenseProfile(
        id: 'redirect-test',
        name: 'Redirect test',
        host: 'firewall.example.test',
        username: 'api-user',
        apiKey: 'test-key',
      ),
    );
    addTearDown(client.dispose);

    expect(client.debugOptions.followRedirects, isFalse);
    expect(client.debugOptions.maxRedirects, 0);
  });
}
