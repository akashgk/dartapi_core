import 'package:shelf/shelf.dart';
import 'api_exception.dart';

/// A middleware that catches any unhandled exception from downstream handlers
/// and delegates to [onError] to produce a custom [ApiException].
///
/// Add this at the top of your pipeline so it wraps all other middleware
/// and route handlers. The returned [ApiException] determines the HTTP
/// status code and error message sent to the client.
///
/// ```dart
/// final handler = Pipeline()
///     .addMiddleware(globalExceptionMiddleware(
///       onError: (error, stackTrace) {
///         if (error is DatabaseException) {
///           return ApiException(503, 'Database unavailable');
///         }
///         return ApiException(500, 'Something went wrong');
///       },
///     ))
///     .addMiddleware(loggingMiddleware())
///     .addHandler(router.handler);
/// ```
Middleware globalExceptionMiddleware({
  required ApiException Function(Object error, StackTrace stackTrace) onError,
}) {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } catch (e, st) {
        final apiEx = onError(e, st);
        return Response(
          apiEx.statusCode,
          body: '{"error":"${apiEx.message}"}',
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
