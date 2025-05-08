import 'package:shelf/shelf.dart';

/// A simple middleware that logs incoming HTTP requests and responses.
///
/// Logs include:
/// - HTTP method and request URI
/// - Response status code
///
/// Useful for development and debugging purposes.
Middleware loggingMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final now = DateTime.now().toIso8601String();
      print('📌 [$now] Request: ${request.method} ${request.requestedUri}');
      final response = await innerHandler(request);
      print(
        '📌 Response: ${request.requestedUri}, Status ${response.statusCode}',
      );
      return response;
    };
  };
}
