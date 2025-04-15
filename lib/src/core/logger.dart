import 'package:shelf/shelf.dart';
import 'dart:developer';

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
