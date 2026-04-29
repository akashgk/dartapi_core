import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _req({Map<String, String>? headers}) =>
    Request('GET', Uri.parse('http://localhost/test'), headers: headers ?? {});

void main() {
  group('requestIdMiddleware', () {
    late Handler handler;

    setUp(() {
      handler = requestIdMiddleware()((req) => Response.ok('ok'));
    });

    test('adds X-Request-Id header to response', () async {
      final res = await handler(_req());
      expect(res.headers['x-request-id'], isNotNull);
      expect(res.headers['x-request-id'], isNotEmpty);
    });

    test('propagates existing X-Request-Id from request', () async {
      final res = await handler(
        _req(headers: {'X-Request-Id': 'my-trace-123'}),
      );
      expect(res.headers['x-request-id'], equals('my-trace-123'));
    });

    test('generates unique IDs for each request', () async {
      final r1 = await handler(_req());
      final r2 = await handler(_req());
      expect(
        r1.headers['x-request-id'],
        isNot(equals(r2.headers['x-request-id'])),
      );
    });

    test('stores request ID in request context', () async {
      String? capturedId;
      final h = requestIdMiddleware()((req) {
        capturedId = req.context['requestId'] as String?;
        return Response.ok('ok');
      });
      await h(_req());
      expect(capturedId, isNotNull);
      expect(capturedId, isNotEmpty);
    });

    test('context ID matches response header', () async {
      String? contextId;
      final h = requestIdMiddleware()((req) {
        contextId = req.context['requestId'] as String?;
        return Response.ok('ok');
      });
      final res = await h(_req());
      expect(contextId, equals(res.headers['x-request-id']));
    });

    test('custom header name is used', () async {
      final h = requestIdMiddleware(headerName: 'X-Trace-Id')(
        (req) => Response.ok('ok'),
      );
      final res = await h(_req());
      expect(res.headers['x-trace-id'], isNotNull);
      expect(res.headers['x-request-id'], isNull);
    });

    test('does not overwrite existing headers on response', () async {
      final h = requestIdMiddleware()(
        (req) => Response.ok('ok', headers: {'X-Custom': 'value'}),
      );
      final res = await h(_req());
      expect(res.headers['x-custom'], equals('value'));
      expect(res.headers['x-request-id'], isNotNull);
    });
  });
}
