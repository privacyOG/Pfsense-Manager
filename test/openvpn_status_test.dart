import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/openvpn_status.dart';

void main() {
  group('OpenVPN status', () {
    test('counts nested client connections across server records', () {
      final servers = [
        OpenVpnServerStatus.fromJson({
          'name': 'remote-access',
          'mode': 'server_tls_user',
          'port': 1194,
          'conns': [
            {
              'common_name': 'phone',
              'remote_host': '198.51.100.10:443',
              'status': 'connected',
            },
            {
              'common_name': 'laptop',
              'remote_host': '198.51.100.11:443',
              'status': 'connected',
            },
          ],
        }),
        OpenVpnServerStatus.fromJson({
          'name': 'site-to-site',
          'conns': [
            {'common_name': 'branch-office'},
          ],
        }),
      ];

      expect(openVpnConnectionCount(servers), 3);
      expect(servers.first.connections.first.displayName, 'phone');
      expect(servers.first.displayName, 'remote-access');
    });

    test('handles empty server status safely', () {
      final server = OpenVpnServerStatus.fromJson({});

      expect(server.displayName, 'OpenVPN');
      expect(server.connections, isEmpty);
      expect(openVpnConnectionCount([server]), 0);
    });
  });
}
