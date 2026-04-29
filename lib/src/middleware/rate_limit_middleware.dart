import 'dart:collection';
import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Token-bucket rate limiter middleware.
///
/// Each unique key (IP address by default) gets a bucket of [maxRequests]
/// tokens that refills fully after every [window]. When the bucket is empty
/// the request is rejected with `429 Too Many Requests`.
///
/// ```dart
/// Pipeline()
///   .addMiddleware(rateLimitMiddleware(
///     maxRequests: 60,
///     window: Duration(minutes: 1),
///   ))
///   .addHandler(router.handler)
/// ```
///
/// Supply a custom [keyExtractor] to key by user ID, API key, etc.:
///
/// ```dart
/// rateLimitMiddleware(
///   maxRequests: 1000,
///   keyExtractor: (req) =>
///       (req.context['user'] as Map?)?['sub'] as String? ??
///       _clientIp(req),
/// )
/// ```
Middleware rateLimitMiddleware({
  int maxRequests = 100,
  Duration window = const Duration(minutes: 1),
  String Function(Request)? keyExtractor,
}) {
  final buckets = HashMap<String, _Bucket>();

  return (Handler inner) {
    return (Request request) async {
      final key =
          keyExtractor != null ? keyExtractor(request) : _clientIp(request);

      final now = DateTime.now();
      final bucket = buckets.putIfAbsent(
        key,
        () => _Bucket(maxRequests, now, window),
      );

      if (now.isAfter(bucket.windowEnd)) {
        bucket
          ..tokens = maxRequests
          ..windowEnd = now.add(window);
      }

      if (bucket.tokens <= 0) {
        final retryAfterSeconds = bucket.windowEnd.difference(now).inSeconds;
        final retryAfter = retryAfterSeconds > 0 ? retryAfterSeconds : 1;
        return Response(
          429,
          body: jsonEncode({'error': 'Too many requests'}),
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': retryAfter.toString(),
            'X-RateLimit-Limit': maxRequests.toString(),
            'X-RateLimit-Remaining': '0',
            'X-RateLimit-Reset':
                bucket.windowEnd.millisecondsSinceEpoch.toString(),
          },
        );
      }

      bucket.tokens--;

      final response = await inner(request);
      return response.change(
        headers: {
          ...response.headersAll.map((k, v) => MapEntry(k, v.join(','))),
          'X-RateLimit-Limit': maxRequests.toString(),
          'X-RateLimit-Remaining': bucket.tokens.toString(),
          'X-RateLimit-Reset':
              bucket.windowEnd.millisecondsSinceEpoch.toString(),
        },
      );
    };
  };
}

class _Bucket {
  int tokens;
  DateTime windowEnd;
  _Bucket(this.tokens, DateTime start, Duration window)
    : windowEnd = start.add(window);
}

String _clientIp(Request request) =>
    request.headers['x-forwarded-for']?.split(',').first.trim() ??
    request.headers['x-real-ip'] ??
    'unknown';
