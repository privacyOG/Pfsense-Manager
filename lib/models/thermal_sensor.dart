import 'dashboard_helpers.dart';

class ThermalSensor {
  const ThermalSensor({required this.name, required this.temperatureC});
  final String name;
  final double temperatureC;
}

List<ThermalSensor> parseThermalSensors(Map<String, dynamic> json) {
  final found = <String, double>{};

  void add(String name, dynamic raw) {
    final value = parseTemperature(raw);
    if (value == null || value < -30 || value > 125) return;
    if (name == 'F' || name.toLowerCase().contains('fahrenheit')) return;
    found[name] = value;
  }

  void parseEntry(String key, dynamic value) {
    final label = _labelFor(key);
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final objectName = nullableText(map['name']) ??
          nullableText(map['label']) ??
          nullableText(map['description']) ??
          nullableText(map['descr']) ??
          label;
      final celsius = map['c'] ?? map['celsius'] ?? map['temp_c'] ??
          map['temperature'] ?? map['value'];
      if (celsius != null) add(objectName, celsius);
      return;
    }
    if (value is List) {
      for (final item in value) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final name = nullableText(map['name']) ??
              nullableText(map['label']) ??
              nullableText(map['descr']) ??
              'System sensor';
          final celsius = map['temp_c'] ?? map['temperature'] ?? map['c'] ?? map['value'];
          if (celsius != null) add(name, celsius);
        }
      }
      return;
    }
    add(label, value);
  }

  for (final entry in json.entries) {
    final lower = entry.key.toLowerCase();
    if (lower.contains('temp') || lower.contains('thermal')) {
      if (entry.value is Map) {
        for (final child in (entry.value as Map).entries) {
          parseEntry(child.key.toString(), child.value);
        }
      } else {
        parseEntry(entry.key, entry.value);
      }
    }
  }

  if (found.isEmpty && json['temp_c'] != null) {
    add('System sensor', json['temp_c']);
  }

  final result = found.entries
      .map((entry) => ThermalSensor(name: entry.key, temperatureC: entry.value))
      .toList();
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

String _labelFor(String raw) {
  final parts = raw.replaceAll('.', ' ').replaceAll('_', ' ').split(' ');
  final cpuIndex = parts.indexOf('cpu');
  if (cpuIndex >= 0 && cpuIndex + 1 < parts.length) {
    return 'CPU ${parts[cpuIndex + 1]}';
  }
  final coreIndex = parts.indexOf('core');
  if (coreIndex >= 0 && coreIndex + 1 < parts.length) {
    return 'Core ${parts[coreIndex + 1]}';
  }
  if (raw == 'temp_c') return 'System sensor';
  return parts
      .where((part) => part.isNotEmpty && part != 'temperature' && part != 'temp')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
