import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/utils/firewall_rule_validation.dart';

void main() {
  FirewallRule validRule({
    String? protocol = 'tcp',
    List<String> interfaces = const ['lan'],
    bool floating = false,
    String stateType = 'keep state',
    String? gateway,
    String? dnpipe,
    String? pdnpipe,
    String? defaultQueue,
    String? ackQueue,
    bool sourceInverted = false,
    String source = 'any',
    int? placement,
  }) {
    return FirewallRule(
      id: '7',
      interfaces: interfaces,
      type: 'pass',
      ipProtocol: 'inet',
      protocol: protocol,
      sourceNetwork: source,
      sourceInverted: sourceInverted,
      destinationNetwork: '192.168.1.10',
      destinationPort: protocol == 'tcp' ? '443' : null,
      floating: floating,
      quick: floating,
      direction: floating ? 'in' : 'any',
      stateType: stateType,
      gateway: gateway,
      dnpipe: dnpipe,
      pdnpipe: pdnpipe,
      defaultQueue: defaultQueue,
      ackQueue: ackQueue,
      placement: placement,
    );
  }

  test('accepts a complete valid advanced rule', () {
    final rule = validRule(
      interfaces: const ['wan', 'lan'],
      floating: true,
      gateway: 'WAN_FAILOVER',
      dnpipe: 'Download',
      pdnpipe: 'Upload',
      defaultQueue: 'qDefault',
      ackQueue: 'qAck',
      placement: 2,
    ).copyWith(
      tcpFlagsOutOf: const ['syn', 'ack'],
      tcpFlagsSet: const ['syn'],
    );

    expect(validateFirewallRule(rule).isValid, isTrue);
  });

  test('multiple interfaces require floating mode', () {
    final result = validateFirewallRule(
      validRule(interfaces: const ['wan', 'lan']),
    );

    expect(result.errorFor('interface'), contains('floating'));
  });

  test('address inversion cannot be combined with any', () {
    final result = validateFirewallRule(
      validRule(sourceInverted: true, source: 'any'),
    );

    expect(result.errorFor('source'), contains('cannot invert'));
  });

  test('source and destination aliases or ascending ranges are accepted', () {
    final rule = validRule().copyWith(
      sourcePort: 'TrustedPorts',
      destinationPort: '8000:8080',
    );

    expect(validateFirewallRule(rule).isValid, isTrue);
  });

  test('descending or out-of-range ports are rejected', () {
    final descending = validateFirewallRule(
      validRule().copyWith(destinationPort: '9000:8000'),
    );
    final outside = validateFirewallRule(
      validRule().copyWith(sourcePort: '70000'),
    );

    expect(descending.errorFor('destination_port'), contains('greater'));
    expect(outside.errorFor('source_port'), contains('1 and 65535'));
  });

  test('ports are rejected for protocols without port semantics', () {
    final result = validateFirewallRule(
      validRule(protocol: 'icmp').copyWith(destinationPort: '443'),
    );

    expect(result.errorFor('destination_port'), contains('TCP and UDP'));
  });

  test('SYN proxy requires TCP and cannot use a gateway', () {
    final nonTcp = validateFirewallRule(
      validRule(protocol: 'udp', stateType: 'synproxy state'),
    );
    final routed = validateFirewallRule(
      validRule(stateType: 'synproxy state', gateway: 'WAN_GW'),
    );

    expect(nonTcp.errorFor('statetype'), contains('requires TCP'));
    expect(routed.errorFor('gateway'), contains('cannot be used'));
  });

  test('required TCP flags must also be selected in out-of flags', () {
    final result = validateFirewallRule(
      validRule().copyWith(
        tcpFlagsOutOf: const ['syn'],
        tcpFlagsSet: const ['ack'],
      ),
    );

    expect(result.errorFor('tcp_flags_set'), contains('also be selected'));
  });

  test('outbound limiter depends on a different inbound limiter', () {
    final missing = validateFirewallRule(validRule(pdnpipe: 'Upload'));
    final same = validateFirewallRule(
      validRule(dnpipe: 'Limit', pdnpipe: 'Limit'),
    );

    expect(missing.errorFor('pdnpipe'), contains('requires an inbound'));
    expect(same.errorFor('pdnpipe'), contains('must be different'));
  });

  test('ACK queue depends on a different default queue', () {
    final missing = validateFirewallRule(validRule(ackQueue: 'qAck'));
    final same = validateFirewallRule(
      validRule(defaultQueue: 'qMain', ackQueue: 'qMain'),
    );

    expect(missing.errorFor('ackqueue'), contains('requires a default'));
    expect(same.errorFor('ackqueue'), contains('must be different'));
  });

  test('literal address family must match the rule IP version', () {
    final ipv6OnV4 = validateFirewallRule(
      validRule().copyWith(sourceNetwork: '2001:db8::1'),
    );
    final ipv4OnV6 = validateFirewallRule(
      validRule().copyWith(
        ipProtocol: 'inet6',
        sourceNetwork: '192.0.2.5',
        destinationNetwork: '2001:db8::2',
      ),
    );

    expect(ipv6OnV4.errorFor('source'), contains('IPv4 only'));
    expect(ipv4OnV6.errorFor('source'), contains('IPv6 only'));
  });

  test('installed schema enums and placement bounds are enforced', () {
    final operation = PfRestOperationCapability(
      path: '/api/v2/firewall/rule',
      method: 'POST',
      requestFields: {
        'body:type': const PfRestFieldConstraint(
          name: 'type',
          location: 'body',
          required: true,
          allowedValues: ['pass', 'block'],
        ),
        'body:interface': const PfRestFieldConstraint(
          name: 'interface',
          location: 'body',
          required: true,
        ),
        'body:ipprotocol': const PfRestFieldConstraint(
          name: 'ipprotocol',
          location: 'body',
          required: true,
          allowedValues: ['inet'],
        ),
        'body:source': const PfRestFieldConstraint(
          name: 'source',
          location: 'body',
          required: true,
        ),
        'body:destination': const PfRestFieldConstraint(
          name: 'destination',
          location: 'body',
          required: true,
        ),
        'body:placement': const PfRestFieldConstraint(
          name: 'placement',
          location: 'body',
          required: false,
          minimum: 0,
          maximum: 10,
        ),
      },
      tags: const {'Firewall'},
    );
    final result = validateFirewallRule(
      validRule(placement: 11).copyWith(type: 'reject'),
      operation: operation,
    );

    expect(result.errorFor('type'), contains('supported'));
    expect(result.errorFor('placement'), contains('schema range'));
  });
}
