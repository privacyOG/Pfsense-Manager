import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.url});

  final String version;
  final String notes;
  final Uri url;
}

class ReleaseCheckService {
  ReleaseCheckService({Dio? client}) : _client = client ?? Dio();

  final Dio _client;

  Future<ReleaseInfo?> check() async {
    final installed = await PackageInfo.fromPlatform();
    final endpoint = Uri.https(
      'api.github.com',
      '/repos/privacyOG/Pfsense-Manager/releases/latest',
    );
    final response = await _client.getUri<Map<String, dynamic>>(endpoint);
    final data = response.data;
    if (data == null) return null;

    final tag = (data['tag_name'] as String? ?? '').trim();
    final page = Uri.tryParse(data['html_url'] as String? ?? '');
    if (tag.isEmpty || page == null) return null;
    if (!isNewer(tag, installed.version)) return null;

    return ReleaseInfo(
      version: normalize(tag),
      notes: (data['body'] as String? ?? '').trim(),
      url: page,
    );
  }

  static bool isNewer(String available, String installed) {
    final left = _parse(available);
    final right = _parse(installed);
    if (left == null || right == null) return false;
    for (var index = 0; index < 3; index++) {
      if (left[index] != right[index]) return left[index] > right[index];
    }
    return false;
  }

  static String normalize(String value) {
    var normalized = value.trim();
    if (normalized.toLowerCase().startsWith('v')) {
      normalized = normalized.substring(1);
    }
    return normalized.split('+').first.split('-').first;
  }

  static List<int>? _parse(String value) {
    final parts = normalize(value).split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }
}
