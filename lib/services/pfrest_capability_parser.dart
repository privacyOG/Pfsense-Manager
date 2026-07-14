import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/pfrest_capabilities.dart';

const _httpMethods = <String>{
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
  'trace',
};

PfRestCapabilities parsePfRestCapabilities({
  required String profileId,
  required dynamic document,
  DateTime? loadedAt,
}) {
  final root = _openApiRoot(document);
  if (root == null) {
    throw const FormatException('OpenAPI document is missing or malformed.');
  }
  final paths = _asMap(root['paths']);
  if (paths == null) {
    throw const FormatException('OpenAPI document does not contain paths.');
  }

  final operations = <String, PfRestOperationCapability>{};
  final packageTags = <String>{};
  final declaredTags = root['tags'];
  if (declaredTags is List) {
    for (final value in declaredTags) {
      final tag = _asMap(value)?['name']?.toString().trim();
      if (tag != null && tag.isNotEmpty) packageTags.add(tag);
    }
  }

  for (final pathEntry in paths.entries) {
    final path = pathEntry.key.trim();
    if (!_isSafeRelativePath(path)) continue;
    final pathItem = _resolveMap(pathEntry.value, root);
    if (pathItem == null) continue;
    final pathParameters = _parameterList(pathItem['parameters']);

    for (final methodEntry in pathItem.entries) {
      final method = methodEntry.key.toLowerCase();
      if (!_httpMethods.contains(method)) continue;
      final operation = _resolveMap(methodEntry.value, root);
      if (operation == null) continue;

      final tags = <String>{};
      final rawTags = operation['tags'];
      if (rawTags is List) {
        for (final rawTag in rawTags) {
          final tag = rawTag?.toString().trim();
          if (tag != null && tag.isNotEmpty) {
            tags.add(tag);
            packageTags.add(tag);
          }
        }
      }

      final fields = <String, PfRestFieldConstraint>{};
      _addParameterFields(
        fields,
        [...pathParameters, ..._parameterList(operation['parameters'])],
        root,
      );
      _addRequestBodyFields(fields, operation['requestBody'], root);

      final capability = PfRestOperationCapability(
        path: path,
        method: method.toUpperCase(),
        summary: _reportedText(operation['summary']),
        operationId: _reportedText(operation['operationId']),
        tags: tags,
        requestFields: fields,
      );
      operations[PfRestCapabilities.operationKey(path, method)] = capability;
    }
  }

  final info = _asMap(root['info']);
  return PfRestCapabilities(
    profileId: profileId,
    status: PfRestCapabilityStatus.available,
    apiVersion: _reportedText(info?['version']),
    openApiVersion:
        _reportedText(root['openapi']) ?? _reportedText(root['swagger']),
    schemaFingerprint: _schemaFingerprint(root),
    loadedAt: loadedAt ?? DateTime.now(),
    operations: operations,
    packageTags: packageTags,
  );
}

void _addParameterFields(
  Map<String, PfRestFieldConstraint> fields,
  List<dynamic> parameters,
  Map<String, dynamic> root,
) {
  for (final parameterValue in parameters) {
    final parameter = _resolveMap(parameterValue, root);
    if (parameter == null) continue;
    final name = _reportedText(parameter['name']);
    final location = _reportedText(parameter['in'])?.toLowerCase();
    if (name == null || location == null) continue;
    final schema = _resolvedSchema(parameter['schema'], root);
    final field = _fieldConstraint(
      name: name,
      location: location,
      required: parameter['required'] == true || location == 'path',
      schema: schema,
    );
    fields['$location:$name'] = field;
  }
}

void _addRequestBodyFields(
  Map<String, PfRestFieldConstraint> fields,
  dynamic requestBodyValue,
  Map<String, dynamic> root,
) {
  final requestBody = _resolveMap(requestBodyValue, root);
  if (requestBody == null) return;
  final content = _asMap(requestBody['content']);
  if (content == null || content.isEmpty) return;

  Map<String, dynamic>? media;
  final preferred = content['application/json'];
  if (preferred != null) media = _asMap(preferred);
  if (media == null) {
    for (final entry in content.entries) {
      if (entry.key.toLowerCase().contains('json')) {
        media = _asMap(entry.value);
        if (media != null) break;
      }
    }
  }
  media ??= _asMap(content.values.first);
  if (media == null) return;

  final schema = _resolvedSchema(media['schema'], root);
  if (schema == null) return;
  final flattened = _flattenComposedSchema(schema, root);
  final properties = _asMap(flattened['properties']);
  if (properties == null) return;
  final requiredNames = <String>{};
  final required = flattened['required'];
  if (required is List) {
    for (final value in required) {
      final name = value?.toString();
      if (name != null && name.isNotEmpty) requiredNames.add(name);
    }
  }

  for (final entry in properties.entries) {
    final propertySchema = _resolvedSchema(entry.value, root) ?? const {};
    final field = _fieldConstraint(
      name: entry.key,
      location: 'body',
      required: requiredNames.contains(entry.key),
      schema: _flattenComposedSchema(propertySchema, root),
    );
    fields['body:${entry.key}'] = field;
  }
}

PfRestFieldConstraint _fieldConstraint({
  required String name,
  required String location,
  required bool required,
  required Map<String, dynamic>? schema,
}) {
  final source = schema ?? const <String, dynamic>{};
  final enumValues = source['enum'];
  return PfRestFieldConstraint(
    name: name,
    location: location,
    required: required,
    type: _reportedText(source['type']),
    format: _reportedText(source['format']),
    minimum: _number(source['minimum']),
    maximum: _number(source['maximum']),
    minLength: _integer(source['minLength']),
    maxLength: _integer(source['maxLength']),
    pattern: _reportedText(source['pattern']),
    allowedValues:
        enumValues is List ? List<Object?>.unmodifiable(enumValues) : const [],
    defaultValue: source['default'],
    description: _reportedText(source['description']),
    readOnly: source['readOnly'] == true,
    writeOnly: source['writeOnly'] == true,
  );
}

Map<String, dynamic> _flattenComposedSchema(
  Map<String, dynamic> schema,
  Map<String, dynamic> root,
) {
  final result = <String, dynamic>{...schema};
  final mergedProperties = <String, dynamic>{};
  final mergedRequired = <String>{};

  final ownProperties = _asMap(schema['properties']);
  if (ownProperties != null) mergedProperties.addAll(ownProperties);
  final ownRequired = schema['required'];
  if (ownRequired is List) {
    mergedRequired.addAll(ownRequired.map((value) => value.toString()));
  }

  final allOf = schema['allOf'];
  if (allOf is List) {
    for (final item in allOf) {
      final resolved = _resolvedSchema(item, root);
      if (resolved == null) continue;
      final flattened = _flattenComposedSchema(resolved, root);
      final properties = _asMap(flattened['properties']);
      if (properties != null) mergedProperties.addAll(properties);
      final required = flattened['required'];
      if (required is List) {
        mergedRequired.addAll(required.map((value) => value.toString()));
      }
      for (final entry in flattened.entries) {
        if (entry.key == 'properties' ||
            entry.key == 'required' ||
            entry.key == 'allOf') {
          continue;
        }
        result.putIfAbsent(entry.key, () => entry.value);
      }
    }
  }

  if (mergedProperties.isNotEmpty) result['properties'] = mergedProperties;
  if (mergedRequired.isNotEmpty) result['required'] = mergedRequired.toList();
  result.remove('allOf');
  return result;
}

Map<String, dynamic>? _resolvedSchema(
  dynamic value,
  Map<String, dynamic> root,
) {
  final resolved = _resolveMap(value, root);
  if (resolved == null) return null;
  return _flattenComposedSchema(resolved, root);
}

Map<String, dynamic>? _resolveMap(
  dynamic value,
  Map<String, dynamic> root, [
  Set<String>? visited,
]) {
  final map = _asMap(value);
  if (map == null) return null;
  final reference = map['\$ref']?.toString();
  if (reference == null || reference.isEmpty) return map;
  if (!reference.startsWith('#/')) return null;

  final seen = visited ?? <String>{};
  if (!seen.add(reference)) return null;
  dynamic resolved = root;
  for (final segment in reference.substring(2).split('/')) {
    final node = _asMap(resolved);
    if (node == null) return null;
    resolved = node[_decodeReferenceSegment(segment)];
  }
  final resolvedMap = _resolveMap(resolved, root, seen);
  if (resolvedMap == null) return null;
  return <String, dynamic>{
    ...resolvedMap,
    for (final entry in map.entries)
      if (entry.key != '\$ref') entry.key: entry.value,
  };
}

List<dynamic> _parameterList(dynamic value) {
  return value is List ? value : const [];
}

Map<String, dynamic>? _openApiRoot(dynamic value) {
  dynamic decoded = value;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return null;
    }
  }
  final map = _asMap(decoded);
  if (map == null) return null;
  if (_asMap(map['paths']) != null) return map;
  if (map.containsKey('data')) return _openApiRoot(map['data']);
  return null;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

bool _isSafeRelativePath(String path) {
  if (!path.startsWith('/') || path.startsWith('//') || path.contains('\\')) {
    return false;
  }
  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  for (final rawSegment in path.split('/')) {
    if (rawSegment.isEmpty) continue;
    String decoded;
    try {
      decoded = Uri.decodeComponent(rawSegment);
    } on FormatException {
      return false;
    }
    if (decoded == '.' || decoded == '..') return false;
  }
  return true;
}

String _schemaFingerprint(Map<String, dynamic> root) {
  final canonical = jsonEncode(_canonicalValue(root));
  return sha256.convert(utf8.encode(canonical)).toString();
}

dynamic _canonicalValue(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalValue).toList();
  return value;
}

String _decodeReferenceSegment(String value) {
  return value.replaceAll('~1', '/').replaceAll('~0', '~');
}

String? _reportedText(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

num? _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

int? _integer(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
