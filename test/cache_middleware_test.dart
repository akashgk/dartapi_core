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

  group('cacheMiddleware - per-route via ApiRoute.cacheTtl', () {
    // Mirrors RouterManager: apply effectiveMiddlewares around route.handler.
    Handler buildHandler(ApiRoute route) {
      Handler h = route.handler;
      for (final mw in route.effectiveMiddlewares) {
        h = mw(h);
      }
      return h;
    }

    test('only the route with cacheTtl returns X-Cache headers', () async {
      int cachedCalls = 0;
      int uncachedCalls = 0;

      final cachedRoute = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/expensive',
        cacheTtl: const Duration(minutes: 5),
        typedHandler: (req, _) async {
          cachedCalls++;
          return {'data': cachedCalls};
        },
      );

      final uncachedRoute = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/cheap',
        typedHandler: (req, _) async {
          uncachedCalls++;
          return {'data': uncachedCalls};
        },
      );

      final cachedHandler = buildHandler(cachedRoute);
      final uncachedHandler = buildHandler(uncachedRoute);

      final req1 = Request('GET', Uri.parse('http://localhost/expensive'));
      final req2 = Request('GET', Uri.parse('http://localhost/cheap'));

      // Warm the cached route.
      await cachedHandler(req1);
      final cachedHit = await cachedHandler(req1);
      expect(cachedHit.headers['x-cache'], equals('HIT'));
      expect(cachedCalls, equals(1));

      // Uncached route never sets X-Cache.
      await uncachedHandler(req2);
      final uncachedSecond = await uncachedHandler(req2);
      expect(uncachedSecond.headers['x-cache'], isNull);
      expect(uncachedCalls, equals(2));
    });

    test('each route with cacheTtl has its own isolated cache', () async {
      int aCalls = 0;
      int bCalls = 0;

      final routeA = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/a',
        cacheTtl: const Duration(minutes: 5),
        typedHandler: (req, _) async {
          aCalls++;
          return {'route': 'a'};
        },
      );

      final routeB = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/b',
        cacheTtl: const Duration(minutes: 5),
        typedHandler: (req, _) async {
          bCalls++;
          return {'route': 'b'};
        },
      );

      final handlerA = buildHandler(routeA);
      final handlerB = buildHandler(routeB);

      final reqA = Request('GET', Uri.parse('http://localhost/a'));
      final reqB = Request('GET', Uri.parse('http://localhost/b'));

      await handlerA(reqA);
      await handlerA(reqA);
      await handlerB(reqB);
      await handlerB(reqB);

      expect(aCalls, equals(1));
      expect(bCalls, equals(1));
    });
  });
}
