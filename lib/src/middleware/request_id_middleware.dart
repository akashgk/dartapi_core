import 'dart:math';

import 'package:shelf/shelf.dart';

/// Middleware that attaches a unique `X-Request-Id` header to every
/// request/response pair.
///
/// If the incoming request already carries an `X-Request-Id` header that
/// value is propagated; otherwise a new random ID is generated.
///
/// ```dart
/// Pipeline()
///   .addMiddleware(requestIdMiddleware())
///   .addHandler(router.handler)
/// ```
///
/// The request ID is stored in `request.context['requestId']` so downstream
/// handlers can read it for logging or tracing.
Middleware requestIdMiddleware({
  /// Override the header name. Defaults to `X-Request-Id`.
  String headerName = 'X-Request-Id',
}) {
  return (Handler inner) {
    return (Request request) async {
      final id = request.headers[headerName] ?? _generateId();

      final updatedRequest = request.change(
        context: {...request.context, 'requestId': id},
      );

      final response = await inner(updatedRequest);

      return response.change(
        headers: {
          ...response.headersAll.map((k, v) => MapEntry(k, v.join(','))),
          headerName: id,
        },
      );
    };
  };
}

final _random = Random.secure();

String _generateId() {
  final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
