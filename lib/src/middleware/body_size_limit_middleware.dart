import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Rejects requests whose `Content-Length` exceeds [maxBytes].
///
/// Returns `413 Payload Too Large` before the body is read, so oversized
/// uploads never reach your handler or DTO parser.
///
/// Only checked when the client sends a `Content-Length` header (most HTTP/1.1
/// clients do for POST/PUT/PATCH). Requests without `Content-Length` pass
/// through — add your own streaming limit if you need stricter enforcement.
///
/// ```dart
/// app.enableBodySizeLimit(maxBytes: 512 * 1024); // 512 KB
/// ```
///
/// Default limit: 1 MB.
Middleware bodySizeLimitMiddleware({int maxBytes = 1024 * 1024}) {
  return (Handler inner) {
    return (Request request) async {
      final length = request.contentLength;
      if (length != null && length > maxBytes) {
        return Response(
          413,
          body: jsonEncode({
            'error': 'Payload Too Large',
            'maxBytes': maxBytes,
            'receivedBytes': length,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return inner(request);
    };
  };
}
