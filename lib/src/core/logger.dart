import 'package:shelf/shelf.dart';

/// Logs every request: `METHOD /path STATUS 12ms`.
Middleware loggingMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final sw = Stopwatch()..start();
      final response = await innerHandler(request);
      sw.stop();
      final ts = DateTime.now().toUtc().toIso8601String();
      // ignore: avoid_print
      print('[$ts] ${request.method} ${request.requestedUri.path} ${response.statusCode} ${sw.elapsedMilliseconds}ms');
      return response;
    };
  };
}
