class SmartAttribute {
  const SmartAttribute({
    required this.id,
    required this.name,
    required this.value,
    required this.worst,
    required this.threshold,
    required this.rawValue,
  });

  final int id;
  final String name;
  final int value;
  final int worst;
  final int threshold;
  final String rawValue;

  bool get failing => value != 0 && threshold != 0 && value <= threshold;

  factory SmartAttribute.fromJson(Map<String, dynamic> json) {
    return SmartAttribute(
      id: _parseInt(json['id'] ?? json['attr_id']),
      name: (json['attribute_name'] ?? json['name'] ?? 'Unknown').toString().trim(),
      value: _parseInt(json['value']),
      worst: _parseInt(json['worst']),
      threshold: _parseInt(json['thresh'] ?? json['threshold']),
      rawValue: (json['raw_value'] ?? '0').toString().trim(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^\d-]'), '')) ?? 0;
    return 0;
  }
}

class SmartDrive {
  const SmartDrive({
    required this.device,
    required this.description,
    required this.healthPassed,
    this.temperatureC,
    this.powerOnHours,
    this.reallocatedSectors,
    this.pendingSectors,
    this.wearLevelingCount,
    this.attributes = const [],
  });

  final String device;
  final String description;
  final bool healthPassed;
  final double? temperatureC;
  final int? powerOnHours;
  final int? reallocatedSectors;
  final int? pendingSectors;
  final int? wearLevelingCount;
  final List<SmartAttribute> attributes;

  factory SmartDrive.fromJson(Map<String, dynamic> json) {
    final statusRaw =
        (json['smart_status'] ?? json['health_status'] ?? '').toString().toUpperCase();
    final healthPassed = statusRaw.contains('PASS') || statusRaw == 'OK';

    final attrs = (json['attributes'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SmartAttribute.fromJson)
        .toList();

    int? rawForId(int id) {
      for (final a in attrs) {
        if (a.id == id) {
          return int.tryParse(a.rawValue.replaceAll(RegExp(r'[^\d]'), ''));
        }
      }
      return null;
    }

    int? rawForHint(String hint) {
      for (final a in attrs) {
        if (a.name.toLowerCase().contains(hint.toLowerCase())) {
          return int.tryParse(a.rawValue.replaceAll(RegExp(r'[^\d]'), ''));
        }
      }
      return null;
    }

    return SmartDrive(
      device: (json['device'] ?? 'unknown').toString(),
      description: (json['description'] ?? json['model'] ?? '').toString().trim(),
      healthPassed: healthPassed,
      temperatureC: _parseDouble(json['temperature_c'] ?? json['temperature']),
      powerOnHours: rawForId(9) ?? rawForHint('power_on'),
      reallocatedSectors: rawForId(5) ?? rawForHint('reallocat'),
      pendingSectors: rawForId(197) ?? rawForHint('pending'),
      wearLevelingCount: rawForId(177) ?? rawForHint('wear'),
      attributes: attrs,
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
