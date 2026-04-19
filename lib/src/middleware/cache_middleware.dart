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
/// ```dart
/// Pipeline()
///   .addMiddleware(cacheMiddleware(ttl: Duration(minutes: 10)))
///   .addHandler(router.handler)
/// ```
///
/// Use a custom [keyExtractor] to control the cache key:
///
/// ```dart
/// cacheMiddleware(
///   keyExtractor: (req) => '${req.url.path}?${req.url.query}',
/// )
/// ```
///
/// Cached responses include an `X-Cache: HIT` or `X-Cache: MISS` header.
Middleware cacheMiddleware({
  Duration ttl = const Duration(minutes: 5),
  String Function(Request)? keyExtractor,
}) {
  final cache = <String, _CachedResponse>{};

  return (Handler inner) {
    return (Request request) async {
      if (request.method != 'GET') return inner(request);

      final key =
          keyExtractor?.call(request) ?? request.requestedUri.toString();

      final cached = cache[key];
      if (cached != null && !cached.isExpired) {
        return Response(
          cached.statusCode,
          body: cached.body,
          headers: {...cached.headers, 'x-cache': 'HIT'},
        );
      }

      final response = await inner(request);

      if (response.statusCode == 200) {
        final bodyBytes = await response.read().expand((b) => b).toList();
        cache[key] = _CachedResponse(
          statusCode: response.statusCode,
          headers: Map<String, String>.from(response.headers),
          body: bodyBytes,
          expiresAt: DateTime.now().add(ttl),
        );
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
