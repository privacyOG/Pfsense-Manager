import 'dart:convert';

import '../models/administration_management.dart';
import '../models/pfrest_capabilities.dart';

class AdministrationValidationResult {
  const AdministrationValidationResult(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
  String get summary => isValid
      ? ''
      : errors.length == 1
          ? errors.values.first
          : 'Correct ${errors.length} fields before continuing.';
}

Map<String, dynamic> normaliseAdministrationValues({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
}) {
  final result = <String, dynamic>{};
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body') continue;
    if (!values.containsKey(field.name)) continue;
    final value = values[field.name];
    result[field.name] = _normalise(value, field);
  }
  return result;
}

AdministrationValidationResult validateAdministrationValues({
  required Map<String, dynamic> values,
  required PfRestOperationCapability operation,
  bool editing = false,
}) {
  final errors = <String, String>{};
  for (final field in operation.requestFields.values) {
    if (field.location.toLowerCase() != 'body' || field.readOnly) continue;
    final value = values[field.name];
    final secret = isAdministrationSecretField(field);
    final empty = _isEmpty(value);
    if (field.required && empty && !(editing && secret)) {
      errors[field.name] = '${_label(field.name)} is required.';
      continue;
    }
    if (empty) continue;

    final text = value is String ? value.trim() : value.toString();
    if (field.minLength != null && text.length < field.minLength!) {
      errors[field.name] =
          '${_label(field.name)} must contain at least ${field.minLength} characters.';
      continue;
    }
    if (field.maxLength != null && text.length > field.maxLength!) {
      errors[field.name] =
          '${_label(field.name)} cannot exceed ${field.maxLength} characters.';
      continue;
    }
    if (field.allowedValues.isNotEmpty &&
        !field.allowedValues.map((item) => item?.toString()).contains(text)) {
      errors[field.name] = '${_label(field.name)} has an unsupported value.';
      continue;
    }
    if (field.type == 'integer' || field.type == 'number') {
      final number = value is num ? value : num.tryParse(text);
      if (number == null) {
        errors[field.name] = '${_label(field.name)} must be numeric.';
      } else if (!field.permitsNumber(number)) {
        errors[field.name] = '${_label(field.name)} is outside the allowed range.';
      }
    }
  }

  final password = values['password']?.toString() ?? '';
  final confirmation = values['password_confirm']?.toString() ??
      values['confirm_password']?.toString() ?? '';
  if (password.isNotEmpty &&
      confirmation.isNotEmpty &&
      password != confirmation) {
    errors['password_confirm'] = 'Password confirmation does not match.';
  }

  final minPoll = int.tryParse(values['ntpminpoll']?.toString() ?? '');
  final maxPoll = int.tryParse(values['ntpmaxpoll']?.toString() ?? '');
  if (minPoll != null && maxPoll != null && maxPoll < minPoll) {
    errors['ntpmaxpoll'] = 'Maximum poll interval cannot be below minimum.';
  }

  return AdministrationValidationResult(Map.unmodifiable(errors));
}

Object? _normalise(Object? value, PfRestFieldConstraint field) {
  if (value is! String) return copyAdministrationValue(value);
  final text = value.trim();
  if (text.isEmpty) return text;
  if (field.type == 'integer') return int.tryParse(text) ?? text;
  if (field.type == 'number') return num.tryParse(text) ?? text;
  if (field.type == 'boolean') {
    return const {'true', '1', 'yes', 'on'}.contains(text.toLowerCase());
  }
  if (field.type == 'array' || field.type == 'object') {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }
  return text;
}

bool _isEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  return false;
}

String _label(String name) => name
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');