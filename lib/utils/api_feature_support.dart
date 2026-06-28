import 'api_exception.dart';

class UnsupportedApiFeatureException extends ApiException {
  const UnsupportedApiFeatureException(String feature)
      : feature = feature,
        super('$feature is not supported by this pfSense REST API installation.');

  final String feature;
}

class ApiFeatureSupportCache {
  final Map<String, bool> _support = {};

  bool isKnownUnsupported(String feature) => _support[feature] == false;

  void markSupported(String feature) {
    _support[feature] = true;
  }

  void markUnsupported(String feature) {
    _support[feature] = false;
  }

  void reset() => _support.clear();
}

bool isUnsupportedEndpointError(ApiException error) {
  return !error.isNetworkError &&
      !error.isTimeout &&
      !error.isAuthError &&
      (error.statusCode == 404 ||
          error.statusCode == 405 ||
          error.statusCode == 501);
}

Future<T> requireApiFeature<T>(
  ApiFeatureSupportCache cache,
  String feature,
  Future<T> Function() request,
) async {
  if (cache.isKnownUnsupported(feature)) {
    throw UnsupportedApiFeatureException(feature);
  }

  try {
    final result = await request();
    cache.markSupported(feature);
    return result;
  } on ApiException catch (error) {
    if (isUnsupportedEndpointError(error)) {
      cache.markUnsupported(feature);
      throw UnsupportedApiFeatureException(feature);
    }
    rethrow;
  }
}
