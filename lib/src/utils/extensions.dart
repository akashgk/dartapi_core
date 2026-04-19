import 'package:shelf/shelf.dart';
import '../core/api_exception.dart';
import 'validator.dart';

/// Extension methods on `Map<String, dynamic>` for typed, validated key extraction.
extension MapExtensions on Map<String, dynamic> {
  /// Extracts a key from the map, verifies its type, and runs optional validators.
  ///
  /// Throws [ApiException] 422 if the key is missing, the wrong type, or fails validation.
  ///
  /// ```dart
  /// final name = json.verifyKey<String>('name');
  /// final age = json.verifyKey<int>('age', validators: [MinValidator(18)]);
  /// ```
  T verifyKey<T>(String key, {List<Validators<T>> validators = const []}) {
    if (!containsKey(key)) {
      throw ApiException(422, 'Missing required field "$key"');
    }

    final value = this[key];

    if (value is! T) {
      throw ApiException(422, 'Field "$key" must be a ${_jsonTypeName<T>()}');
    }

    for (final validator in validators) {
      if (!validator.validate(value)) {
        throw ApiException(422, validator.validationErrorMessage);
      }
    }

    return value;
  }
}

/// Extension methods on Shelf's [Request] for typed path and query parameter extraction.
extension RequestExtensions on Request {
  /// Extracts and casts a path parameter by name.
  ///
  /// Path parameters are populated by `shelf_router` (e.g. `/users/<id>`).
  /// Throws [ApiException] 400 if the param is missing or cannot be cast to [T].
  ///
  /// Supported types: [String], [int], [double], [bool].
  ///
  /// ```dart
  /// final id = request.pathParam<int>('id');
  /// final slug = request.pathParam<String>('slug');
  /// ```
  T pathParam<T>(String name) {
    final params =
        (context['shelf_router/params'] as Map<String, String>?) ?? {};
    final value = params[name];
    if (value == null) {
      throw ApiException(400, 'Missing path parameter "$name"');
    }
    return _coerce<T>(name, value);
  }

  /// Extracts and casts a query parameter by name.
  ///
  /// Returns [defaultValue] if the parameter is absent.
  /// Throws [ApiException] 400 if the value cannot be cast to [T].
  ///
  /// Supported types: [String], [int], [double], [bool].
  ///
  /// ```dart
  /// final page = request.queryParam<int>('page', defaultValue: 1);
  /// final search = request.queryParam<String>('q');
  /// ```
  T? queryParam<T>(String name, {T? defaultValue}) {
    final value = url.queryParameters[name];
    if (value == null) return defaultValue;
    return _coerce<T>(name, value);
  }

  /// Extracts and casts a request header by name (case-insensitive).
  ///
  /// Returns [defaultValue] if the header is absent.
  /// Throws [ApiException] 400 if the value cannot be cast to [T].
  ///
  /// Supported types: [String], [int], [double], [bool].
  ///
  /// ```dart
  /// final locale = request.header<String>('Accept-Language');
  /// final version = request.header<int>('X-Api-Version', defaultValue: 1);
  /// ```
  T? header<T>(String name, {T? defaultValue}) {
    final value = headers[name.toLowerCase()];
    if (value == null) return defaultValue;
    return _coerce<T>(name, value);
  }
}

String _jsonTypeName<T>() => switch (T) {
      const (String) => 'string',
      const (int) => 'integer',
      const (double) => 'number',
      const (bool) => 'boolean',
      _ => T.toString().toLowerCase(),
    };

/// Coerces a URL string value to the requested type [T].
T _coerce<T>(String name, String value) {
  if (T == String) return value as T;
  if (T == int) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw ApiException(400, 'Parameter "$name" must be an integer, got "$value"');
    }
    return parsed as T;
  }
  if (T == double) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      throw ApiException(400, 'Parameter "$name" must be a number, got "$value"');
    }
    return parsed as T;
  }
  if (T == bool) return (value == 'true') as T;
  throw ApiException(
    500,
    'Unsupported parameter type $T for "$name". Use String, int, double, or bool.',
  );
}
