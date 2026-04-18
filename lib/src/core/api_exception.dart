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
