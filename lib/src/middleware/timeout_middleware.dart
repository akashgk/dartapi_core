import 'dart:async';

import 'package:shelf/shelf.dart';

/// Middleware that returns 408 if the inner handler does not respond within [timeout].
///
/// ```dart
/// final handler = Pipeline()
///     .addMiddleware(timeoutMiddleware(Duration(seconds: 30)))
///     .addHandler(router.handler);
/// ```
Middleware timeoutMiddleware(Duration timeout) {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await Future.value(inner(request)).timeout(timeout);
      } on TimeoutException {
        return Response(
          408,
          body: '{"error":"Request Timeout"}',
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
