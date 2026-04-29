import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Handler _makeHandler({
  int maxRequests = 3,
  Duration window = const Duration(minutes: 1),
  String Function(Request)? keyExtractor,
}) => rateLimitMiddleware(
  maxRequests: maxRequests,
  window: window,
  keyExtractor: keyExtractor,
)((req) => Response.ok('ok'));

Request _req({String ip = '1.2.3.4'}) => Request(
  'GET',
  Uri.parse('http://localhost/test'),
  headers: {'X-Forwarded-For': ip},
);

void main() {
  group('rateLimitMiddleware', () {
    test('allows requests within the limit', () async {
      final handler = _makeHandler(maxRequests: 3);
      for (var i = 0; i < 3; i++) {
        final res = await handler(_req());
        expect(res.statusCode, equals(200));
      }
    });

    test('returns 429 when limit is exceeded', () async {
      final handler = _makeHandler(maxRequests: 2);
      await handler(_req());
      await handler(_req());
      final res = await handler(_req());
      expect(res.statusCode, equals(429));
    });

    test('429 response body contains error key', () async {
      final handler = _makeHandler(maxRequests: 1);
      await handler(_req());
      final res = await handler(_req());
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['error'], isNotEmpty);
    });

    test('429 response includes Retry-After header', () async {
      final handler = _makeHandler(maxRequests: 1);
      await handler(_req());
      final res = await handler(_req());
      expect(res.headers['retry-after'], isNotNull);
      expect(int.parse(res.headers['retry-after']!), greaterThan(0));
    });

    test('successful responses include X-RateLimit headers', () async {
      final handler = _makeHandler(maxRequests: 5);
      final res = await handler(_req());
      expect(res.headers['x-ratelimit-limit'], equals('5'));
      expect(res.headers['x-ratelimit-remaining'], isNotNull);
      expect(res.headers['x-ratelimit-reset'], isNotNull);
    });

    test('remaining count decrements with each request', () async {
      final handler = _makeHandler(maxRequests: 3);
      final r1 = await handler(_req());
      final r2 = await handler(_req());
      expect(
        int.parse(r1.headers['x-ratelimit-remaining']!),
        greaterThan(int.parse(r2.headers['x-ratelimit-remaining']!)),
      );
    });

    test('different IPs have independent buckets', () async {
      final handler = _makeHandler(maxRequests: 1);
      await handler(_req(ip: '1.1.1.1'));
      final res1 = await handler(_req(ip: '1.1.1.1'));
      final res2 = await handler(_req(ip: '2.2.2.2'));
      expect(res1.statusCode, equals(429));
      expect(res2.statusCode, equals(200));
    });

    test('custom keyExtractor is used', () async {
      final handler = rateLimitMiddleware(
        maxRequests: 1,
        keyExtractor: (_) => 'fixed-key',
      )((req) => Response.ok('ok'));

      await handler(_req(ip: '1.1.1.1'));
      // Different IP but same key — should still be rate limited
      final res = await handler(_req(ip: '9.9.9.9'));
      expect(res.statusCode, equals(429));
    });

    test('window resets after expiry', () async {
      final handler = _makeHandler(
        maxRequests: 1,
        window: Duration(milliseconds: 50),
      );
      await handler(_req());
      expect((await handler(_req())).statusCode, equals(429));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((await handler(_req())).statusCode, equals(200));
    });
  });
}
