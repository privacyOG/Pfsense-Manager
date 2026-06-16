String? nullableText(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

String textOr(dynamic value, String fallback) => nullableText(value) ?? fallback;

double doubleOrZero(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int intOrZero(dynamic value) {
  if (value is num) return value.round();
  return double.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

String? addressWithPrefix(dynamic address, dynamic subnet) {
  final value = nullableText(address);
  if (value == null) return null;
  final prefix = nullableText(subnet);
  return prefix == null ? value : '$value/$prefix';
}

double? parseTemperature(dynamic value) {
  if (value is num) return value.toDouble();
  final match = RegExp(r'-?\d+(?:\.\d+)?')
      .firstMatch(value?.toString() ?? '');
  return match == null ? null : double.tryParse(match.group(0)!);
}
