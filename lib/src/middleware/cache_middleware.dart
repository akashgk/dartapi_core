import 'package:shelf/shelf.dart';

class _CachedResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
  final DateTime expiresAt;

  _CachedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory response cache middleware for GET requests.
///
/// Caches responses with status 200 for [ttl] (default 5 minutes).
/// Only GET requests are cached; all other methods pass through.
///
/// Uses an LRU (Least Recently Used) eviction policy capped at [maxEntries]
/// (default 500). On a cache hit the entry is promoted to most-recently-used;
/// when the cap is reached the oldest unused entry is evicted first.
///
/// **Global** — wraps the entire router, caches all GET endpoints:
/// ```dart
/// Pipeline()
///   .addMiddleware(cacheMiddleware(ttl: Duration(minutes: 10)))
///   .addHandler(router.handler)
/// ```
///
/// **Per-route** — cache only specific routes via `ApiRoute.cacheTtl`:
/// ```dart
/// ApiRoute(
///   method: ApiMethod.get,
///   path: '/products',
///   cacheTtl: Duration(minutes: 10),
///   typedHandler: (req, _) async => fetchProducts(),
/// )
/// ```
///
/// Use a custom [keyExtractor] to control the cache key:
/// ```dart
/// cacheMiddleware(
///   keyExtractor: (req) => '${req.url.path}?${req.url.query}',
/// )
/// ```
///
/// Cached responses include an `X-Cache: HIT` or `X-Cache: MISS` header.
Middleware cacheMiddleware({
  Duration ttl = const Duration(minutes: 5),
  int maxEntries = 500,
  String Function(Request)? keyExtractor,
}) {
  // LinkedHashMap preserves insertion order — first entry is LRU.
  final cache = <String, _CachedResponse>{};

  void promote(String key, _CachedResponse value) {
    cache.remove(key);
    cache[key] = value;
  }

  return (Handler inner) {
    return (Request request) async {
      if (request.method != 'GET') return inner(request);

      final key =
          keyExtractor?.call(request) ?? request.requestedUri.toString();

      final cached = cache[key];
      if (cached != null) {
        if (!cached.isExpired) {
          promote(key, cached);
          return Response(
            cached.statusCode,
            body: cached.body,
            headers: {...cached.headers, 'x-cache': 'HIT'},
          );
        }
        cache.remove(key);
      }

      final response = await inner(request);

      if (response.statusCode == 200) {
        final bodyBytes = await response.read().expand((b) => b).toList();
        final entry = _CachedResponse(
          statusCode: response.statusCode,
          headers: Map<String, String>.from(response.headers),
          body: bodyBytes,
          expiresAt: DateTime.now().add(ttl),
        );

        // Evict LRU (first) entry if at capacity.
        if (cache.length >= maxEntries) {
          cache.remove(cache.keys.first);
        }
        cache[key] = entry;

        return Response(
          response.statusCode,
          body: bodyBytes,
          headers: {...response.headers, 'x-cache': 'MISS'},
        );
      }

      return response;
    };
  };
}
