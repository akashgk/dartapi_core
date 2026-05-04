import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('bodySizeLimitMiddleware', () {
    Response ok(Request _) => Response.ok('ok');

    Request makePost(String path, {int? contentLength}) {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (contentLength != null) 'Content-Length': '$contentLength',
      };
      return Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: headers,
      );
    }

    test('passes request below limit', () async {
      final handler = Pipeline()
          .addMiddleware(bodySizeLimitMiddleware(maxBytes: 100))
          .addHandler(ok);
      final res = await handler(makePost('/data', contentLength: 50));
      expect(res.statusCode, equals(200));
    });

    test('returns 413 when Content-Length exceeds limit', () async {
      final handler = Pipeline()
          .addMiddleware(bodySizeLimitMiddleware(maxBytes: 100))
          .addHandler(ok);
      final res = await handler(makePost('/data', contentLength: 200));
      expect(res.statusCode, equals(413));
    });

    test('413 body is valid JSON with error details', () async {
      final handler = Pipeline()
          .addMiddleware(bodySizeLimitMiddleware(maxBytes: 100))
          .addHandler(ok);
      final res = await handler(makePost('/data', contentLength: 200));
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['error'], equals('Payload Too Large'));
      expect(body['maxBytes'], equals(100));
      expect(body['receivedBytes'], equals(200));
    });

    test('passes request without Content-Length header', () async {
      final handler = Pipeline()
          .addMiddleware(bodySizeLimitMiddleware(maxBytes: 10))
          .addHandler(ok);
      // No content-length header — should pass through
      final req = Request('POST', Uri.parse('http://localhost/data'));
      final res = await handler(req);
      expect(res.statusCode, equals(200));
    });

    test('uses default 1 MB limit', () async {
      final handler = Pipeline()
          .addMiddleware(bodySizeLimitMiddleware())
          .addHandler(ok);
      // Exactly at limit is rejected (> not >=), so 1 MB + 1 byte should fail
      final res = await handler(
        makePost('/data', contentLength: 1024 * 1024 + 1),
      );
      expect(res.statusCode, equals(413));
    });
  });
}
