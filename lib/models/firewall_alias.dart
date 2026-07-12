class FirewallAliasEntry {
  const FirewallAliasEntry({
    required this.value,
    this.description = '',
  });

  final String value;
  final String description;

  FirewallAliasEntry copyWith({String? value, String? description}) {
    return FirewallAliasEntry(
      value: value ?? this.value,
      description: description ?? this.description,
    );
  }
}

class FirewallAlias {
  const FirewallAlias({
    this.id,
    required this.name,
    required this.type,
    this.description = '',
    this.entries = const [],
  });

  static const supportedTypes = <String>{'host', 'network', 'port'};

  final int? id;
  final String name;
  final String type;
  final String description;
  final List<FirewallAliasEntry> entries;

  bool get isSupportedType => supportedTypes.contains(type.toLowerCase());

  factory FirewallAlias.fromJson(Map<String, dynamic> json) {
    final addresses = _stringValues(
      json['address'],
      delimiter: ' ',
      preserveEmpty: false,
    );
    final details = _stringValues(
      json['detail'],
      delimiter: '||',
      preserveEmpty: true,
    );
    final entries = <FirewallAliasEntry>[];
    for (var index = 0; index < addresses.length; index++) {
      entries.add(
        FirewallAliasEntry(
          value: addresses[index],
          description: index < details.length ? details[index] : '',
        ),
      );
    }

    return FirewallAlias(
      id: _intValue(json['id']),
      name: json['name']?.toString().trim() ?? '',
      type: json['type']?.toString().trim().toLowerCase() ?? '',
      description: (json['descr'] ?? json['description'])?.toString() ?? '',
      entries: List.unmodifiable(entries),
    );
  }

  Map<String, dynamic> toCreatePayload() {
    return {
      'name': name.trim(),
      ...toUpdatePayload(),
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    final normalizedEntries = entries
        .map(
          (entry) => FirewallAliasEntry(
            value: entry.value.trim(),
            description: entry.description.trim(),
          ),
        )
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    return {
      'type': type.trim().toLowerCase(),
      'descr': description.trim(),
      'address': [for (final entry in normalizedEntries) entry.value],
      'detail': [for (final entry in normalizedEntries) entry.description],
    };
  }

  FirewallAlias copyWith({
    int? id,
    String? name,
    String? type,
    String? description,
    List<FirewallAliasEntry>? entries,
  }) {
    return FirewallAlias(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      entries: entries ?? this.entries,
    );
  }
}

List<String> _stringValues(
  dynamic value, {
  required String delimiter,
  required bool preserveEmpty,
}) {
  final values = value is List
      ? value.map((item) => item?.toString().trim() ?? '').toList()
      : (value?.toString() ?? '')
          .split(delimiter)
          .map((item) => item.trim())
          .toList();
  if (preserveEmpty) return List.unmodifiable(values);
  return values.where((item) => item.isNotEmpty).toList(growable: false);
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
