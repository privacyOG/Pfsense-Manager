import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/openvpn_status.dart';
import 'package:pfsense_manager/models/system_service.dart';
import 'package:pfsense_manager/services/system_service_registry.dart';

void main() {
  group('system service instances', () {
    test('preserves OpenVPN instance metadata from pfREST', () {
      final service = SystemService.fromJson({
        'id': 8,
        'name': 'openvpn',
        'description': 'OpenVPN server',
        'enabled': true,
        'status': true,
        'mode': 'server',
        'vpnid': 2,
      });

      expect(service.id, 8);
      expect(service.name, 'openvpn');
      expect(service.enabled, isTrue);
      expect(service.running, isTrue);
      expect(service.mode, 'server');
      expect(service.vpnId, '2');
      expect(service.instanceKey, 'openvpn:8');
      expect(
        service.instanceLabel,
        'OpenVPN server (server · VPN ID 2 · Service #8)',
      );
    });

    test('uses unique instance keys for duplicate service names', () {
      final first = _openVpnService(id: 5, vpnId: '1');
      final second = _openVpnService(id: 8, vpnId: '2');

      expect(first.instanceKey, 'openvpn:5');
      expect(second.instanceKey, 'openvpn:8');
      expect(first.instanceKey, isNot(second.instanceKey));
    });
  });

  group('system service registry', () {
    test('retains every duplicate-name service by ID', () {
      final registry = SystemServiceRegistry();
      registry.replaceAll([
        _openVpnService(id: 5, vpnId: '1'),
        _openVpnService(id: 8, vpnId: '2'),
      ]);

      final matches = registry.findByName('openvpn');
      expect(matches.map((service) => service.id), [5, 8]);
      expect(matches.map((service) => service.vpnId), ['1', '2']);
    });

    test('builds an exact action payload for the selected instance', () {
      final registry = SystemServiceRegistry();
      final selected = _openVpnService(id: 8, vpnId: '2');
      registry.replaceAll([
        _openVpnService(id: 5, vpnId: '1'),
        selected,
      ]);

      expect(
        registry.actionDataForInstance(selected, 'restart'),
        {'id': 8, 'name': 'openvpn', 'action': 'restart'},
      );
    });

    test('rejects ambiguous name-only service control', () {
      final registry = SystemServiceRegistry();
      registry.replaceAll([
        _openVpnService(id: 5, vpnId: '1'),
        _openVpnService(id: 8, vpnId: '2'),
      ]);

      expect(
        () => registry.actionDataForName('openvpn', 'restart'),
        throwsA(isA<StateError>()),
      );
    });

    test('keeps unique name-based service control working', () {
      final registry = SystemServiceRegistry();
      registry.replaceAll([
        SystemService(
          id: 2,
          name: 'unbound',
          displayName: 'DNS Resolver',
          running: true,
        ),
      ]);

      expect(
        registry.actionDataForName('unbound', 'restart'),
        {'id': 2, 'name': 'unbound', 'action': 'restart'},
      );
    });
  });

  group('OpenVPN status matching', () {
    final services = [
      _openVpnService(id: 5, vpnId: '1'),
      _openVpnService(id: 8, vpnId: '2'),
    ];

    test('matches the selected OpenVPN server by vpnid', () {
      final status = OpenVpnServerStatus.fromJson({
        'name': 'Staff VPN',
        'mode': 'server',
        'vpnid': '2',
        'port': '1195',
        'conns': <dynamic>[],
      });

      expect(matchOpenVpnService(status, services)?.id, 8);
    });

    test('does not guess when multiple instances cannot be distinguished', () {
      final status = OpenVpnServerStatus.fromJson({
        'name': 'Unknown VPN',
        'mode': 'server',
        'port': '1194',
        'conns': <dynamic>[],
      });

      expect(matchOpenVpnService(status, services), isNull);
    });

    test('uses a single-instance fallback safely', () {
      final status = OpenVpnServerStatus.fromJson({
        'name': 'Only VPN',
        'conns': <dynamic>[],
      });

      expect(matchOpenVpnService(status, [services.first])?.id, 5);
    });
  });
}

SystemService _openVpnService({required int id, required String vpnId}) {
  return SystemService(
    id: id,
    name: 'openvpn',
    displayName: 'OpenVPN server',
    running: true,
    mode: 'server',
    vpnId: vpnId,
  );
}
