import 'dart:io';

import 'package:shelf/shelf.dart';

/// Middleware that gzip-compresses response bodies when the client supports it.
///
/// Compression is applied only when:
/// - The client sends `Accept-Encoding: gzip`
/// - The response body is at least [threshold] bytes (default 1 KB)
/// - The response does not already have a `Content-Encoding` header
///
/// ```dart
/// Pipeline()
///   .addMiddleware(compressionMiddleware())
///   .addHandler(router.handler)
/// ```
Middleware compressionMiddleware({int threshold = 1024}) {
  return (Handler inner) {
    return (Request request) async {
      final acceptsGzip =
          request.headers['accept-encoding']?.contains('gzip') ?? false;

      final response = await inner(request);

      if (!acceptsGzip) return response;
      if (response.headers.containsKey('content-encoding')) return response;

      final body = await response.read().toList();
      final bytes = body.expand((chunk) => chunk).toList();

      if (bytes.length < threshold) return response;

      final compressed = gzip.encode(bytes);

      final headers = Map<String, String>.from(response.headers)
        ..['content-encoding'] = 'gzip'
        ..['content-length'] = compressed.length.toString();

      return response.change(body: compressed, headers: headers);
    };
  };
}
