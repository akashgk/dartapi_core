/// An exception that carries an HTTP status code and message.
///
/// Throw this from handlers or validators to return a specific HTTP error
/// response rather than a generic 500. For example:
///
/// ```dart
/// throw ApiException(404, 'User not found');
/// throw ApiException(422, 'Invalid email format');
/// ```
class ApiException implements Exception {
  /// The HTTP status code to return (e.g., 400, 404, 422).
  final int statusCode;

  /// A human-readable error message included in the response body.
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when one or more request fields fail validation.
///
/// Unlike [ApiException], this carries a list of per-field errors so the client
/// receives all failures in a single response rather than one at a time.
///
/// Caught by [ApiRoute] and serialised as:
/// ```json
/// {"errors": [{"field": "email", "message": "Invalid email address"}, ...]}
/// ```
///
/// Use [Map.validateAll] to build and throw this automatically.
class ValidationException implements Exception {
  /// Each entry has `"field"` and `"message"` keys.
  final List<Map<String, String>> errors;

  const ValidationException(this.errors);

  @override
  String toString() => 'ValidationException: $errors';
}
