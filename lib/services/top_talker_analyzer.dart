import 'dart:io';
import 'dart:math' as math;

import '../models/dashboard.dart';
import '../models/network_state.dart';
import '../models/top_talker.dart';

class TopTalkerAnalyzer {
  final Map<String, int> _previousBytesByHost = {};
  DateTime? _previousSampleAt;

  List<TopTalker> build({
    required List<NetworkState> states,
    required List<InterfaceStatus> interfaces,
    int limit = 25,
    DateTime? capturedAt,
  }) {
    final now = capturedAt ?? DateTime.now();
    final elapsedSeconds = _previousSampleAt == null
        ? null
        : math.max(
            0.5,
            now.difference(_previousSampleAt!).inMilliseconds / 1000,
          );
    final subnets = _interfaceSubnets(interfaces);
    final aggregates = <String, _TopTalkerAggregate>{};

    for (final state in states) {
      final endpoint = _selectLocalEndpoint(state, subnets);
      if (endpoint == null || endpoint.host.isEmpty || endpoint.host == '*') {
        continue;
      }
      final aggregate = aggregates.putIfAbsent(
        endpoint.host,
        () => _TopTalkerAggregate(endpoint.host),
      );
      aggregate.bytes += state.bytes;
      aggregate.connections++;
      if (aggregate.interface.isEmpty) {
        aggregate.interface = endpoint.interfaceName.isNotEmpty
            ? endpoint.interfaceName
            : state.interface;
      }
    }

    final currentBytesByHost = <String, int>{
      for (final aggregate in aggregates.values) aggregate.host: aggregate.bytes,
    };
    final talkers = aggregates.values.map((aggregate) {
      final previousBytes = _previousBytesByHost[aggregate.host];
      final bytesPerSecond = elapsedSeconds == null || previousBytes == null
          ? 0.0
          : math.max(0, aggregate.bytes - previousBytes) / elapsedSeconds;
      return TopTalker(
        ipAddress: aggregate.host,
        bytes: aggregate.bytes,
        bytesPerSecond: bytesPerSecond,
        connections: aggregate.connections,
        interface: aggregate.interface,
      );
    }).toList()
      ..sort((a, b) {
        final rateCompare = b.bytesPerSecond.compareTo(a.bytesPerSecond);
        if (rateCompare != 0) return rateCompare;
        return b.bytes.compareTo(a.bytes);
      });

    _previousBytesByHost
      ..clear()
      ..addAll(currentBytesByHost);
    _previousSampleAt = now;

    return talkers.take(limit).toList();
  }

  void reset() {
    _previousBytesByHost.clear();
    _previousSampleAt = null;
  }
}

List<_InterfaceSubnet> _interfaceSubnets(List<InterfaceStatus> interfaces) {
  return interfaces
      .expand((interface) => [
            _InterfaceSubnet.fromInterface(interface, interface.ipv4Address),
            _InterfaceSubnet.fromInterface(interface, interface.ipv6Address),
          ])
      .whereType<_InterfaceSubnet>()
      .toList();
}

_SelectedEndpoint? _selectLocalEndpoint(
  NetworkState state,
  List<_InterfaceSubnet> subnets,
) {
  final source = _hostAddress(state.sourceIp);
  final destination = _hostAddress(state.destinationIp);
  final sourceSubnet = _matchingSubnet(source, subnets);
  final destinationSubnet = _matchingSubnet(destination, subnets);

  if (sourceSubnet != null && destinationSubnet == null) {
    return _SelectedEndpoint(source.address, sourceSubnet.label);
  }
  if (destinationSubnet != null && sourceSubnet == null) {
    return _SelectedEndpoint(destination.address, destinationSubnet.label);
  }
  if (sourceSubnet != null && destinationSubnet != null) {
    return _SelectedEndpoint(source.address, sourceSubnet.label);
  }

  final sourcePrivate = _isPrivateAddress(source.internetAddress);
  final destinationPrivate = _isPrivateAddress(destination.internetAddress);
  if (sourcePrivate && !destinationPrivate) {
    return _SelectedEndpoint(source.address, state.interface);
  }
  if (destinationPrivate && !sourcePrivate) {
    return _SelectedEndpoint(destination.address, state.interface);
  }
  if (sourcePrivate) return _SelectedEndpoint(source.address, state.interface);
  if (destinationPrivate) {
    return _SelectedEndpoint(destination.address, state.interface);
  }

  return source.address.isEmpty ? null : _SelectedEndpoint(source.address, state.interface);
}

_InterfaceSubnet? _matchingSubnet(
  _HostAddress host,
  List<_InterfaceSubnet> subnets,
) {
  final address = host.internetAddress;
  if (address == null) return null;
  for (final subnet in subnets) {
    if (subnet.contains(address)) return subnet;
  }
  return null;
}

_HostAddress _hostAddress(String value) {
  final host = _endpointHost(value);
  final parsed = InternetAddress.tryParse(host);
  if (parsed == null) return _HostAddress(host, null);
  return _HostAddress(parsed.address.toLowerCase(), parsed);
}

String _endpointHost(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('[')) {
    final end = trimmed.indexOf(']');
    if (end > 1) return _withoutZone(trimmed.substring(1, end));
  }

  final zoneFree = _withoutZone(trimmed);
  final lastColon = zoneFree.lastIndexOf(':');
  final hasDot = zoneFree.contains('.');
  if (hasDot && lastColon > -1) {
    final port = zoneFree.substring(lastColon + 1);
    if (int.tryParse(port) != null) {
      return zoneFree.substring(0, lastColon);
    }
  }
  return zoneFree;
}

String _withoutZone(String value) {
  final zoneIndex = value.indexOf('%');
  if (zoneIndex < 0) return value;
  return value.substring(0, zoneIndex);
}

bool _isPrivateAddress(InternetAddress? address) {
  if (address == null) return false;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254) ||
        first == 127;
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    final first = bytes[0];
    final second = bytes[1];
    return (first & 0xfe) == 0xfc ||
        (first == 0xfe && (second & 0xc0) == 0x80) ||
        bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
  }
  return false;
}

class _InterfaceSubnet {
  const _InterfaceSubnet({
    required this.networkAddress,
    required this.prefixLength,
    required this.label,
  });

  final InternetAddress networkAddress;
  final int prefixLength;
  final String label;

  static _InterfaceSubnet? fromInterface(
    InterfaceStatus interface,
    String? cidr,
  ) {
    if (cidr == null || cidr.trim().isEmpty) return null;
    final parts = cidr.split('/');
    final address = InternetAddress.tryParse(_endpointHost(parts.first));
    if (address == null) return null;
    final bits = address.rawAddress.length * 8;
    final prefix = parts.length > 1 ? int.tryParse(parts[1]) ?? bits : bits;
    if (prefix < 0 || prefix > bits) return null;
    return _InterfaceSubnet(
      networkAddress: address,
      prefixLength: prefix,
      label: _interfaceLabel(interface),
    );
  }

  bool contains(InternetAddress address) {
    if (address.type != networkAddress.type) return false;
    final target = address.rawAddress;
    final network = networkAddress.rawAddress;
    final wholeBytes = prefixLength ~/ 8;
    final remainingBits = prefixLength % 8;

    for (var index = 0; index < wholeBytes; index++) {
      if (target[index] != network[index]) return false;
    }
    if (remainingBits == 0) return true;

    final mask = (0xff << (8 - remainingBits)) & 0xff;
    return (target[wholeBytes] & mask) == (network[wholeBytes] & mask);
  }
}

String _interfaceLabel(InterfaceStatus interface) {
  final description = interface.description.trim();
  if (description.isNotEmpty) return description;
  final name = interface.name.trim();
  if (name.isNotEmpty) return name.toUpperCase();
  final hardware = interface.hardwareInterface.trim();
  return hardware.isEmpty ? '' : hardware;
}

class _HostAddress {
  const _HostAddress(this.address, this.internetAddress);

  final String address;
  final InternetAddress? internetAddress;
}

class _SelectedEndpoint {
  const _SelectedEndpoint(this.host, this.interfaceName);

  final String host;
  final String interfaceName;
}

class _TopTalkerAggregate {
  _TopTalkerAggregate(this.host);

  final String host;
  String interface = '';
  int bytes = 0;
  int connections = 0;
}
