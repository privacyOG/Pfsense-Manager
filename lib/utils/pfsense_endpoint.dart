class PfSenseEndpoint {
  const PfSenseEndpoint({
    required this.host,
    required this.port,
    required this.useHttps,
  });

  final String host;
  final int port;
  final bool useHttps;

  String get baseUrl => buildPfSenseBaseUrl(
        host: host,
        port: port,
        useHttps: useHttps,
      );
}

PfSenseEndpoint parsePfSenseEndpoint(
  String input, {
  required int fallbackPort,
  required bool fallbackUseHttps,
  bool requireHttps = false,
}) {
  final text = input.trim();
  if (text.isEmpty) {
    throw const FormatException('Enter a host, IP address, or HTTPS URL.');
  }
  if (text.contains(RegExp(r'\s'))) {
    throw const FormatException('The endpoint cannot contain spaces.');
  }
  if (fallbackPort < 1 || fallbackPort > 65535) {
    throw const FormatException('Enter a valid port between 1 and 65535.');
  }

  final hasExplicitScheme = text.contains('://');
  final fallbackScheme = fallbackUseHttps ? 'https' : 'http';
  final candidate = hasExplicitScheme
      ? text
      : _withScheme(text, fallbackScheme);
  if (_rawAuthority(candidate).endsWith(':')) {
    throw const FormatException('Enter a valid port between 1 and 65535.');
  }

  late final Uri uri;
  try {
    uri = Uri.parse(candidate);
  } on FormatException catch (error) {
    throw FormatException(_messageForUriError(error));
  }

  late final String host;
  late final int port;
  try {
    host = uri.host.trim();
    port = uri.hasPort ? uri.port : fallbackPort;
  } on FormatException catch (error) {
    if (_isPortUriError(error)) {
      throw const FormatException('Enter a valid port between 1 and 65535.');
    }
    throw const FormatException('Enter a valid host or IP address.');
  }

  if (!uri.hasAuthority || host.isEmpty) {
    throw const FormatException('Enter a valid host or IP address.');
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw const FormatException('Only HTTPS endpoints are supported.');
  }
  if (requireHttps && scheme != 'https') {
    throw const FormatException('HTTPS is required for API security.');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'Remove the username or password from the endpoint.',
    );
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const FormatException(
      'Enter the firewall address without an API path.',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'Remove query parameters and fragments from the endpoint.',
    );
  }
  if (port < 1 || port > 65535) {
    throw const FormatException('Enter a valid port between 1 and 65535.');
  }

  return PfSenseEndpoint(
    host: host,
    port: port,
    useHttps: scheme == 'https',
  );
}

String buildPfSenseBaseUrl({
  required String host,
  required int port,
  required bool useHttps,
}) {
  final endpoint = parsePfSenseEndpoint(
    host,
    fallbackPort: port,
    fallbackUseHttps: useHttps,
  );
  final scheme = endpoint.useHttps ? 'https' : 'http';
  final formattedHost = endpoint.host.contains(':')
      ? '[${endpoint.host}]'
      : endpoint.host;
  return '$scheme://$formattedHost:${endpoint.port}';
}

String _withScheme(String input, String scheme) {
  if (input.startsWith('[')) return '$scheme://$input';
  final colonCount = ':'.allMatches(input).length;
  if (colonCount > 1) return '$scheme://[$input]';
  return '$scheme://$input';
}

String _rawAuthority(String candidate) {
  final schemeEnd = candidate.indexOf('://');
  if (schemeEnd < 0) return '';
  final start = schemeEnd + 3;
  var end = candidate.length;
  for (final delimiter in ['/', '?', '#']) {
    final index = candidate.indexOf(delimiter, start);
    if (index >= 0 && index < end) end = index;
  }
  return candidate.substring(start, end);
}

String _messageForUriError(FormatException error) {
  if (_isPortUriError(error)) {
    return 'Enter a valid port between 1 and 65535.';
  }
  return 'Enter a valid host, IP address, or HTTPS URL.';
}

bool _isPortUriError(FormatException error) {
  final message = error.message.toString().toLowerCase();
  return message.contains('invalid port') ||
      message.contains('port number') ||
      message.contains('port out of range');
}
