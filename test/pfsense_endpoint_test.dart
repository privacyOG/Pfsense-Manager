import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/utils/pfsense_endpoint.dart';

void main() {
  group('pfSense endpoint parsing', () {
    test('parses accepted IPv6 endpoint forms', () {
      final bare = parsePfSenseEndpoint(
        '2001:db8::1',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );
      final bracketed = parsePfSenseEndpoint(
        '[2001:db8::1]',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );
      final bracketedWithPort = parsePfSenseEndpoint(
        '[2001:db8::1]:8443',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );
      final fullUrl = parsePfSenseEndpoint(
        'https://[2001:db8::1]:8443',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );

      expect(bare.host, '2001:db8::1');
      expect(bare.port, 443);
      expect(bracketed.host, '2001:db8::1');
      expect(bracketed.port, 443);
      expect(bracketedWithPort.host, '2001:db8::1');
      expect(bracketedWithPort.port, 8443);
      expect(fullUrl.host, '2001:db8::1');
      expect(fullUrl.port, 8443);
      expect(fullUrl.useHttps, isTrue);
    });

    test('keeps IPv4 and DNS profiles compatible', () {
      final ipv4 = parsePfSenseEndpoint(
        '192.168.1.1',
        fallbackPort: 10443,
        fallbackUseHttps: true,
        requireHttps: true,
      );
      final dns = parsePfSenseEndpoint(
        'firewall.example.test:8443',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );

      expect(ipv4.host, '192.168.1.1');
      expect(ipv4.port, 10443);
      expect(dns.host, 'firewall.example.test');
      expect(dns.port, 8443);
    });

    test('accepts a trailing slash but rejects an API path', () {
      final endpoint = parsePfSenseEndpoint(
        'https://firewall.example.test:8443/',
        fallbackPort: 443,
        fallbackUseHttps: true,
        requireHttps: true,
      );

      expect(endpoint.host, 'firewall.example.test');
      expect(endpoint.port, 8443);
      expect(
        () => parsePfSenseEndpoint(
          'https://firewall.example.test/api/v2',
          fallbackPort: 443,
          fallbackUseHttps: true,
          requireHttps: true,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('without an API path'),
          ),
        ),
      );
    });

    test('rejects user information, query parameters and fragments', () {
      expect(
        () => parsePfSenseEndpoint(
          'https://user:secret@firewall.example.test',
          fallbackPort: 443,
          fallbackUseHttps: true,
          requireHttps: true,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('username or password'),
          ),
        ),
      );
      expect(
        () => parsePfSenseEndpoint(
          'https://firewall.example.test?source=profile',
          fallbackPort: 443,
          fallbackUseHttps: true,
          requireHttps: true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parsePfSenseEndpoint(
          'https://firewall.example.test#settings',
          fallbackPort: 443,
          fallbackUseHttps: true,
          requireHttps: true,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported schemes and insecure URLs in the form', () {
      expect(
        () => parsePfSenseEndpoint(
          'ftp://firewall.example.test',
          fallbackPort: 443,
          fallbackUseHttps: true,
          requireHttps: true,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Only HTTPS'),
          ),
        ),
      );
      expect(
        () => parsePfSenseEndpoint(
          'http://firewall.example.test',
          fallbackPort: 80,
          fallbackUseHttps: false,
          requireHttps: true,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('HTTPS is required'),
          ),
        ),
      );
    });

    test('rejects malformed and out-of-range ports', () {
      for (final input in [
        'firewall.example.test:',
        'firewall.example.test:notaport',
        '[2001:db8::1]:70000',
        'https://firewall.example.test:0',
      ]) {
        expect(
          () => parsePfSenseEndpoint(
            input,
            fallbackPort: 443,
            fallbackUseHttps: true,
            requireHttps: true,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('valid port'),
            ),
          ),
          reason: input,
        );
      }
    });
  });

  group('pfSense profile endpoint normalisation', () {
    test('constructs IPv6 base URLs with one scheme, host and port', () {
      final profile = PfSenseProfile(
        id: 'ipv6',
        name: 'IPv6 firewall',
        host: 'https://[2001:db8::1]:8443',
        port: 443,
        username: 'api-user',
        apiKey: 'test-key',
      );

      expect(profile.host, '2001:db8::1');
      expect(profile.port, 8443);
      expect(profile.useHttps, isTrue);
      expect(profile.baseUrl, 'https://[2001:db8::1]:8443');
      expect('[2001:db8::1]'.allMatches(profile.baseUrl), hasLength(1));
    });

    test('normalises legacy bracketed IPv6 metadata during loading', () {
      final profile = PfSenseProfile.fromJson({
        'id': 'legacy-ipv6',
        'name': 'Legacy IPv6',
        'host': '[2001:db8::5]:10443',
        'port': 443,
        'useHttps': true,
        'allowSelfSignedCert': true,
        'username': 'api-user',
      });

      expect(profile.host, '2001:db8::5');
      expect(profile.port, 10443);
      expect(profile.baseUrl, 'https://[2001:db8::5]:10443');
      expect(profile.toJson()['host'], '2001:db8::5');
      expect(profile.toJson()['port'], 10443);
    });

    test('keeps explicit ports in IPv4 and DNS base URLs', () {
      final ipv4 = PfSenseProfile(
        id: 'ipv4',
        name: 'IPv4 firewall',
        host: '192.168.1.1',
        port: 8443,
        username: 'api-user',
        apiKey: 'test-key',
      );
      final dns = PfSenseProfile(
        id: 'dns',
        name: 'DNS firewall',
        host: 'firewall.example.test',
        port: 443,
        username: 'api-user',
        apiKey: 'test-key',
      );

      expect(ipv4.baseUrl, 'https://192.168.1.1:8443');
      expect(dns.baseUrl, 'https://firewall.example.test:443');
    });

    test('retains non-HTTPS metadata outside the secured profile form', () {
      final profile = PfSenseProfile(
        id: 'legacy-http',
        name: 'Legacy HTTP',
        host: 'firewall.example.test',
        port: 80,
        useHttps: false,
        username: 'api-user',
        apiKey: 'test-key',
      );

      expect(profile.useHttps, isFalse);
      expect(profile.baseUrl, 'http://firewall.example.test:80');
    });
  });
}
