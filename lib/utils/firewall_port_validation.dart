const Set<String> firewallPortProtocols = {'tcp', 'udp', 'tcp/udp'};

bool firewallProtocolSupportsPorts(String? protocol) {
  return firewallPortProtocols.contains(protocol?.trim().toLowerCase());
}

class FirewallPortRangeValidation {
  const FirewallPortRangeValidation({this.fromError, this.toError});

  final String? fromError;
  final String? toError;

  bool get isValid => fromError == null && toError == null;
}

FirewallPortRangeValidation validateFirewallDestinationPortRange({
  required String protocol,
  required String from,
  required String to,
}) {
  if (!firewallProtocolSupportsPorts(protocol)) {
    return const FirewallPortRangeValidation();
  }

  final fromText = from.trim();
  final toText = to.trim();

  if (fromText.isEmpty && toText.isEmpty) {
    return const FirewallPortRangeValidation();
  }

  if (fromText.isEmpty) {
    return const FirewallPortRangeValidation(
      fromError: 'Enter a starting port.',
    );
  }

  final fromPort = int.tryParse(fromText);
  if (fromPort == null || fromPort < 1 || fromPort > 65535) {
    return const FirewallPortRangeValidation(
      fromError: 'Enter a port from 1 to 65535.',
    );
  }

  if (toText.isEmpty) {
    return const FirewallPortRangeValidation();
  }

  final toPort = int.tryParse(toText);
  if (toPort == null || toPort < 1 || toPort > 65535) {
    return const FirewallPortRangeValidation(
      toError: 'Enter a port from 1 to 65535.',
    );
  }

  if (fromPort > toPort) {
    return const FirewallPortRangeValidation(
      toError: 'Ending port must be greater than or equal to starting port.',
    );
  }

  return const FirewallPortRangeValidation();
}
