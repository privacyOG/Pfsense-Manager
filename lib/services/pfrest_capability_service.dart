import '../models/pfrest_capabilities.dart';
import '../utils/api_exception.dart';
import 'api_client.dart';
import 'pfrest_capability_parser.dart';

const pfRestOpenApiSchemaPath = '/api/v2/schema/openapi';

class PfRestCapabilityService {
  PfRestCapabilityService(
    this._client, {
    required String profileId,
    DateTime Function()? clock,
  })  : _profileId = profileId,
        _clock = clock ?? DateTime.now,
        _current = PfRestCapabilities.notLoaded(profileId);

  final PfSenseApiClient _client;
  final String _profileId;
  final DateTime Function() _clock;
  PfRestCapabilities _current;
  Future<PfRestCapabilities>? _refreshRequest;
  bool _disposed = false;

  PfRestCapabilities get current => _current;

  bool supports(String path, String method) {
    return _current.supports(path, method);
  }

  PfRestFieldConstraint? requestField(
    String path,
    String method,
    String fieldName, {
    String? location,
  }) {
    return _current.requestField(
      path,
      method,
      fieldName,
      location: location,
    );
  }

  Future<PfRestCapabilities> refresh() {
    _ensureActive();
    final existing = _refreshRequest;
    if (existing != null) return existing;

    late final Future<PfRestCapabilities> request;
    request = _load().whenComplete(() {
      if (!_disposed && identical(_refreshRequest, request)) {
        _refreshRequest = null;
      }
    });
    _refreshRequest = request;
    return request;
  }

  Future<PfRestCapabilities> _load() async {
    final loadedAt = _clock();
    PfRestCapabilities next;
    try {
      final response = await _client.get(pfRestOpenApiSchemaPath);
      next = parsePfRestCapabilities(
        profileId: _profileId,
        document: response.data,
        loadedAt: loadedAt,
      );
    } on ApiException catch (error) {
      next = _limitedFromApiError(error, loadedAt);
    } on FormatException {
      next = PfRestCapabilities.limited(
        profileId: _profileId,
        issue: PfRestCapabilityIssue.invalidSchema,
        message:
            'The pfREST OpenAPI response could not be parsed. Basic features remain available, but capability checks are limited.',
        loadedAt: loadedAt,
      );
    } catch (_) {
      next = PfRestCapabilities.limited(
        profileId: _profileId,
        issue: PfRestCapabilityIssue.requestFailed,
        message:
            'Capability discovery failed. Basic features remain available, but endpoint checks may be incomplete.',
        loadedAt: loadedAt,
      );
    }

    if (!_disposed) _current = next;
    return _disposed ? _current : next;
  }

  PfRestCapabilities _limitedFromApiError(
    ApiException error,
    DateTime loadedAt,
  ) {
    if (error.isAuthenticationError) {
      return PfRestCapabilities.limited(
        profileId: _profileId,
        issue: PfRestCapabilityIssue.authentication,
        message:
            'The OpenAPI schema request was not authenticated. Basic features remain available, but capability checks are limited.',
        loadedAt: loadedAt,
      );
    }
    if (error.isPermissionError) {
      return PfRestCapabilities.limited(
        profileId: _profileId,
        issue: PfRestCapabilityIssue.permissionDenied,
        message:
            'The saved credential cannot read the pfREST OpenAPI schema (403). Basic features remain available, but capability checks are limited.',
        loadedAt: loadedAt,
      );
    }
    if (error.isEndpointUnavailable) {
      return PfRestCapabilities.limited(
        profileId: _profileId,
        issue: PfRestCapabilityIssue.schemaUnavailable,
        message:
            'This pfREST installation does not expose the OpenAPI schema. Basic features remain available, but capability checks are limited.',
        loadedAt: loadedAt,
      );
    }
    return PfRestCapabilities.limited(
      profileId: _profileId,
      issue: PfRestCapabilityIssue.requestFailed,
      message:
          'The OpenAPI schema could not be loaded. Basic features remain available, but capability checks are limited.',
      loadedAt: loadedAt,
    );
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('This capability service is no longer active.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshRequest = null;
    _current = PfRestCapabilities.notLoaded(_profileId);
  }
}
