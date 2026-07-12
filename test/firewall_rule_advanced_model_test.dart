import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  Map<String, dynamic> advancedJson() => {
        'id': 27,
        'type': 'pass',
        'interface': ['wan', 'lan'],
        'ipprotocol': 'inet',
        'protocol': 'tcp',
        'source': '!PrivateHosts',
        'source_port': 'WebPorts',
        'destination': 'lan:ip',
        'destination_port': '8000:8080',
        'descr': 'Advanced policy route',
        'disabled': false,
        'log': true,
        'tag': 'policy-route',
        'statetype': 'sloppy state',
        'tcp_flags_any': false,
        'tcp_flags_out_of': ['syn', 'ack'],
        'tcp_flags_set': ['syn'],
        'gateway': 'WAN_FAILOVER',
        'sched': 'BusinessHours',
        'dnpipe': 'DownloadLimiter',
        'pdnpipe': 'UploadLimiter',
        'defaultqueue': 'qDefault',
        'ackqueue': 'qAck',
        'floating': true,
        'quick': true,
        'direction': 'in',
        'tracker': 1700000000,
        'associated_rule_id': 'nat-123',
        'created': {'time': 1700000001, 'username': 'admin'},
        'updated': {'time': 1700000002, 'username': 'operator'},
      };

  test('advanced pfREST fields round-trip without loss', () {
    final rule = FirewallRule.fromJson(advancedJson());
    final create = rule.toCreatePayload();
    final update = rule.toUpdatePayload();

    expect(rule.interfaces, ['wan', 'lan']);
    expect(rule.interface, 'wan, lan');
    expect(rule.sourceNetwork, 'PrivateHosts');
    expect(rule.sourceInverted, isTrue);
    expect(rule.sourcePort, 'WebPorts');
    expect(rule.destinationPort, '8000:8080');
    expect(rule.destinationPortFrom, 8000);
    expect(rule.destinationPortTo, 8080);
    expect(rule.log, isTrue);
    expect(rule.gateway, 'WAN_FAILOVER');
    expect(rule.schedule, 'BusinessHours');
    expect(rule.floating, isTrue);
    expect(rule.quick, isTrue);
    expect(rule.direction, 'in');
    expect(rule.tracker, '1700000000');
    expect(rule.associatedRuleId, 'nat-123');
    expect(rule.createdBy, 'admin');
    expect(rule.updatedBy, 'operator');

    expect(create['interface'], ['wan', 'lan']);
    expect(create['source'], '!PrivateHosts');
    expect(create['source_port'], 'WebPorts');
    expect(create['destination_port'], '8000:8080');
    expect(create['log'], isTrue);
    expect(create['tag'], 'policy-route');
    expect(create['statetype'], 'sloppy state');
    expect(create['tcp_flags_out_of'], ['syn', 'ack']);
    expect(create['tcp_flags_set'], ['syn']);
    expect(create['gateway'], 'WAN_FAILOVER');
    expect(create['sched'], 'BusinessHours');
    expect(create['dnpipe'], 'DownloadLimiter');
    expect(create['pdnpipe'], 'UploadLimiter');
    expect(create['defaultqueue'], 'qDefault');
    expect(create['ackqueue'], 'qAck');
    expect(create['floating'], isTrue);
    expect(create['quick'], isTrue);
    expect(create['direction'], 'in');

    expect(update.containsKey('floating'), isFalse);
    expect(update['quick'], isTrue);
    expect(update['direction'], 'in');
    expect(update.containsKey('tracker'), isFalse);
    expect(update.containsKey('associated_rule_id'), isFalse);
  });

  test('copying a basic edit preserves every untouched advanced value', () {
    final original = FirewallRule.fromJson(advancedJson());
    final edited = original.copyWith(description: 'Changed description');
    final payload = edited.toUpdatePayload();

    expect(edited.description, 'Changed description');
    expect(edited.interfaces, original.interfaces);
    expect(edited.sourceInverted, isTrue);
    expect(edited.sourcePort, 'WebPorts');
    expect(edited.gateway, 'WAN_FAILOVER');
    expect(edited.schedule, 'BusinessHours');
    expect(edited.tcpFlagsOutOf, ['syn', 'ack']);
    expect(payload['gateway'], 'WAN_FAILOVER');
    expect(payload['sched'], 'BusinessHours');
    expect(payload['dnpipe'], 'DownloadLimiter');
    expect(payload['ackqueue'], 'qAck');
  });

  test('update payload explicitly clears nullable advanced fields', () {
    final cleared = FirewallRule.fromJson(advancedJson()).copyWith(
      sourcePort: null,
      destinationPort: null,
      gateway: null,
      schedule: null,
      dnpipe: null,
      pdnpipe: null,
      defaultQueue: null,
      ackQueue: null,
      protocol: null,
    );
    final payload = cleared.toUpdatePayload();

    expect(payload['protocol'], isNull);
    expect(payload['source_port'], isNull);
    expect(payload['destination_port'], isNull);
    expect(payload['gateway'], isNull);
    expect(payload['sched'], isNull);
    expect(payload['dnpipe'], isNull);
    expect(payload['pdnpipe'], isNull);
    expect(payload['defaultqueue'], isNull);
    expect(payload['ackqueue'], isNull);
  });

  test('create payload omits empty nullable fields', () {
    final rule = FirewallRule(
      interface: 'lan',
      sourceNetwork: 'any',
      destinationNetwork: 'any',
    );
    final payload = rule.toCreatePayload();

    expect(payload.containsKey('protocol'), isFalse);
    expect(payload.containsKey('source_port'), isFalse);
    expect(payload.containsKey('destination_port'), isFalse);
    expect(payload.containsKey('gateway'), isFalse);
    expect(payload.containsKey('sched'), isFalse);
  });

  test('schema filtering excludes advanced fields not accepted by operation', () {
    final operation = PfRestOperationCapability(
      path: '/api/v2/firewall/rule',
      method: 'PATCH',
      requestFields: {
        for (final name in const [
          'type',
          'interface',
          'ipprotocol',
          'source',
          'destination',
          'descr',
          'disabled',
        ])
          'body:$name': PfRestFieldConstraint(
            name: name,
            location: 'body',
            required: true,
          ),
      },
      tags: const {'Firewall'},
    );
    final payload = FirewallRule.fromJson(advancedJson())
        .toUpdatePayload(operation: operation);

    expect(payload.keys, containsAll(const [
      'type',
      'interface',
      'ipprotocol',
      'source',
      'destination',
      'descr',
      'disabled',
    ]));
    expect(payload.containsKey('gateway'), isFalse);
    expect(payload.containsKey('log'), isFalse);
    expect(payload.containsKey('tcp_flags_set'), isFalse);
  });

  test('ICMP and floating-only fields follow pfREST conditions', () {
    final icmp = FirewallRule(
      interface: 'wan',
      ipProtocol: 'inet',
      protocol: 'icmp',
      icmpTypes: const ['echoreq'],
      quick: true,
      direction: 'out',
    );
    final payload = icmp.toCreatePayload();

    expect(payload['icmptype'], ['echoreq']);
    expect(payload['floating'], isFalse);
    expect(payload.containsKey('quick'), isFalse);
    expect(payload.containsKey('direction'), isFalse);
  });
}
