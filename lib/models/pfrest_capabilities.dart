enum PfRestCapabilityStatus {
  available,
  limited,
}

enum PfRestCapabilityIssue {
  notLoaded,
  authentication,
  permissionDenied,
  schemaUnavailable,
  invalidSchema,
  requestFailed,
}

class PfRestFieldConstraint {
  const PfRestFieldConstraint({
    required this.name,
    required this.location,
    required this.required,
    this.type,
    this.format,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.allowedValues = const [],
    this.defaultValue,
    this.description,
    this.readOnly = false,
    this.writeOnly = false,
  });

  final String name;
  final String location;
  final bool required;
  final String? type;
  final String? format;
  final num? minimum;
  final num? maximum;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final List<Object?> allowedValues;
  final Object? defaultValue;
  final String? description;
  final bool readOnly;
  final bool writeOnly;

  bool permitsNumber(num value) {
    final lower = minimum;
    final upper = maximum;
    if (lower != null && value < lower) return false;
    if (upper != null && value > upper) return false;
    return true;
  }
}

class PfRestOperationCapability {
  PfRestOperationCapability({
    required this.path,
    required this.method,
    required Map<String, PfRestFieldConstraint> requestFields,
    required Set<String> tags,
    this.summary,
    this.operationId,
  })  : tags = Set.unmodifiable(tags),
        requestFields = Map.unmodifiable(requestFields);

  final String path;
  final String method;
  final String? summary;
  final String? operationId;
  final Set<String> tags;
  final Map<String, PfRestFieldConstraint> requestFields;

  PfRestFieldConstraint? field(String name, {String? location}) {
    if (location != null) {
      return requestFields['${location.toLowerCase()}:$name'];
    }
    for (final field in requestFields.values) {
      if (field.name == name) return field;
    }
    return null;
  }
}

class PfRestCapabilities {
  PfRestCapabilities({
    required this.profileId,
    required this.status,
    required Map<String, PfRestOperationCapability> operations,
    required Set<String> packageTags,
    required this.loadedAt,
    this.issue,
    this.message,
    this.apiVersion,
    this.openApiVersion,
    this.schemaFingerprint,
  })  : packageTags = Set.unmodifiable(packageTags),
        operations = Map.unmodifiable(operations);

  factory PfRestCapabilities.notLoaded(String profileId) {
    return PfRestCapabilities(
      profileId: profileId,
      status: PfRestCapabilityStatus.limited,
      issue: PfRestCapabilityIssue.notLoaded,
      message: 'Capability discovery has not completed for this session.',
      operations: const {},
      packageTags: const {},
      loadedAt: null,
    );
  }

  factory PfRestCapabilities.limited({
    required String profileId,
    required PfRestCapabilityIssue issue,
    required String message,
    DateTime? loadedAt,
  }) {
    return PfRestCapabilities(
      profileId: profileId,
      status: PfRestCapabilityStatus.limited,
      issue: issue,
      message: message,
      operations: const {},
      packageTags: const {},
      loadedAt: loadedAt,
    );
  }

  final String profileId;
  final PfRestCapabilityStatus status;
  final PfRestCapabilityIssue? issue;
  final String? message;
  final String? apiVersion;
  final String? openApiVersion;
  final String? schemaFingerprint;
  final DateTime? loadedAt;
  final Map<String, PfRestOperationCapability> operations;
  final Set<String> packageTags;

  bool get isAvailable => status == PfRestCapabilityStatus.available;
  bool get isLimited => status == PfRestCapabilityStatus.limited;

  bool supports(String path, String method) {
    return operation(path, method) != null;
  }

  PfRestOperationCapability? operation(String path, String method) {
    return operations[_operationKey(path, method)];
  }

  PfRestFieldConstraint? requestField(
    String path,
    String method,
    String fieldName, {
    String? location,
  }) {
    return operation(path, method)?.field(fieldName, location: location);
  }

  Set<String> methodsForPath(String path) {
    final methods = <String>{};
    for (final operation in operations.values) {
      if (operation.path == path) methods.add(operation.method);
    }
    return Set.unmodifiable(methods);
  }

  static String operationKey(String path, String method) {
    return _operationKey(path, method);
  }
}

String _operationKey(String path, String method) {
  return '${method.trim().toUpperCase()} ${path.trim()}';
}
