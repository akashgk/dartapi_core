import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('cacheMiddleware', () {
    int callCount = 0;

    Handler makeHandler({int status = 200}) {
      callCount = 0;
      return (Request req) {
        callCount++;
        return Response(status, body: 'response-$callCount');
      };
    }

    Request makeReq([String path = '/items']) =>
        Request('GET', Uri.parse('http://localhost$path'));

    test('first request is a MISS', () async {
      final handler =
          Pipeline().addMiddleware(cacheMiddleware()).addHandler(makeHandler());
      final res = await handler(makeReq());
      expect(res.headers['x-cache'], equals('MISS'));
    });

    test('second request for same URL is a HIT', () async {
      final handler =
          Pipeline().addMiddleware(cacheMiddleware()).addHandler(makeHandler());
      await handler(makeReq());
      final res = await handler(makeReq());
      expect(res.headers['x-cache'], equals('HIT'));
    });

    test('cached response returns same body', () async {
      final handler =
          Pipeline().addMiddleware(cacheMiddleware()).addHandler(makeHandler());
      final first = await (await handler(makeReq())).readAsString();
      final second = await (await handler(makeReq())).readAsString();
      expect(first, equals(second));
    });

    test('handler is only called once for multiple identical GET requests', () async {
      final handler =
          Pipeline().addMiddleware(cacheMiddleware()).addHandler(makeHandler());
      await handler(makeReq());
      await handler(makeReq());
      await handler(makeReq());
      expect(callCount, equals(1));
    });

    test('different URLs are cached independently', () async {
      final handler =
          Pipeline().addMiddleware(cacheMiddleware()).addHandler(makeHandler());
      final r1 = await handler(makeReq('/a'));
      final r2 = await handler(makeReq('/b'));
      expect(r1.headers['x-cache'], equals('MISS'));
      expect(r2.headers['x-cache'], equals('MISS'));
    });

    test('POST requests bypass cache', () async {
      int postCount = 0;
      final handler = Pipeline().addMiddleware(cacheMiddleware()).addHandler(
        (req) {
          postCount++;
          return Response.ok('post');
        },
      );
      final post = Request('POST', Uri.parse('http://localhost/items'));
      await handler(post);
      await handler(post);
      expect(postCount, equals(2));
    });

    test('non-200 responses are not cached', () async {
      final handler = Pipeline()
          .addMiddleware(cacheMiddleware())
          .addHandler(makeHandler(status: 404));
      final r1 = await handler(makeReq());
      final r2 = await handler(makeReq());
      expect(r1.headers['x-cache'], isNull);
      expect(r2.headers['x-cache'], isNull);
      expect(callCount, equals(2));
    });

    test('expired entries are re-fetched', () async {
      final handler = Pipeline()
          .addMiddleware(cacheMiddleware(ttl: Duration(milliseconds: 50)))
          .addHandler(makeHandler());
      await handler(makeReq());
      await Future<void>.delayed(Duration(milliseconds: 100));
      final res = await handler(makeReq());
      expect(res.headers['x-cache'], equals('MISS'));
      expect(callCount, equals(2));
    });

    test('custom keyExtractor controls cache key', () async {
      final handler = Pipeline()
          .addMiddleware(cacheMiddleware(
            keyExtractor: (req) => req.url.path,
          ))
          .addHandler(makeHandler());
      // Same path, different query — should still HIT
      await handler(Request('GET', Uri.parse('http://localhost/items?page=1')));
      final res = await handler(
          Request('GET', Uri.parse('http://localhost/items?page=2')));
      expect(res.headers['x-cache'], equals('HIT'));
    });

    test('cached body is valid utf8', () async {
      final handler = Pipeline().addMiddleware(cacheMiddleware()).addHandler(
        (req) => Response.ok(jsonEncode({'ok': true}),
            headers: {'content-type': 'application/json'}),
      );
      await handler(makeReq());
      final res = await handler(makeReq());
      final body = await res.readAsString();
      expect(jsonDecode(body), equals({'ok': true}));
    });
  });
}
