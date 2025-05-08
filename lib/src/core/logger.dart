import 'package:shelf/shelf.dart';
import 'dart:developer';

/// A simple middleware that logs incoming HTTP requests and responses.
///
/// Logs include:
/// - HTTP method and request URI
/// - Response status code
///
/// Useful for development and debugging purposes.
/// This uses Dart's built-in `log()` function from `dart:developer`.
Middleware loggingMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      log('📌 Request: ${request.method} ${request.requestedUri}');
      final response = await innerHandler(request);

      log(
        '📌 Response: ${request.requestedUri}, Status ${response.statusCode}',
      );

      return response;
    };
  };
}
