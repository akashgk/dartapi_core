import 'package:shelf/shelf.dart';

/// Singleton registry that accumulates Prometheus-compatible metrics for
/// every request recorded by [metricsMiddleware].
///
/// Read the current snapshot via [serialize], which returns a valid
/// Prometheus text-format 0.0.4 payload.
///
/// Call [reset] in tests between cases to start from a clean slate.
class MetricsRegistry {
  MetricsRegistry._();

  static final MetricsRegistry instance = MetricsRegistry._();

  // key: 'METHOD|/path|status'  value: count
  final Map<String, int> _requestCounts = {};

  // key: 'METHOD|/path'  value: total seconds
  final Map<String, double> _durationSums = {};

  // key: 'METHOD|/path'  value: total request count (== +Inf bucket)
  final Map<String, int> _durationCounts = {};

  // Cumulative histogram bucket counts.
  // key: 'METHOD|/path|le'  value: count of requests with duration <= le
  final Map<String, int> _histogramBuckets = {};

  static const _buckets = [
    0.005,
    0.01,
    0.025,
    0.05,
    0.1,
    0.25,
    0.5,
    1.0,
    2.5,
    5.0,
    10.0,
  ];

  void recordRequest(
    String method,
    String path,
    int status,
    double durationSeconds,
  ) {
    final countKey = '$method|$path|$status';
    _requestCounts[countKey] = (_requestCounts[countKey] ?? 0) + 1;

    final durationKey = '$method|$path';
    _durationSums[durationKey] =
        (_durationSums[durationKey] ?? 0.0) + durationSeconds;
    _durationCounts[durationKey] = (_durationCounts[durationKey] ?? 0) + 1;

    for (final le in _buckets) {
      if (durationSeconds <= le) {
        final bucketKey = '$method|$path|$le';
        _histogramBuckets[bucketKey] = (_histogramBuckets[bucketKey] ?? 0) + 1;
      }
    }
  }

  /// Returns all recorded metrics in Prometheus text format (0.0.4).
  String serialize() {
    final buf = StringBuffer();

    buf.writeln('# HELP http_requests_total Total number of HTTP requests.');
    buf.writeln('# TYPE http_requests_total counter');
    for (final entry in _requestCounts.entries) {
      final parts = entry.key.split('|');
      buf.writeln(
        'http_requests_total{method="${parts[0]}",path="${parts[1]}",status="${parts[2]}"} ${entry.value}',
      );
    }

    buf.writeln(
      '# HELP http_request_duration_seconds HTTP request duration in seconds.',
    );
    buf.writeln('# TYPE http_request_duration_seconds histogram');
    for (final durationKey in _durationSums.keys) {
      final parts = durationKey.split('|');
      final method = parts[0];
      final path = parts[1];

      for (final le in _buckets) {
        final bucketKey = '$method|$path|$le';
        final count = _histogramBuckets[bucketKey] ?? 0;
        buf.writeln(
          'http_request_duration_seconds_bucket{method="$method",path="$path",le="$le"} $count',
        );
      }
      final total = _durationCounts[durationKey] ?? 0;
      buf.writeln(
        'http_request_duration_seconds_bucket{method="$method",path="$path",le="+Inf"} $total',
      );
      buf.writeln(
        'http_request_duration_seconds_sum{method="$method",path="$path"} ${_durationSums[durationKey]}',
      );
      buf.writeln(
        'http_request_duration_seconds_count{method="$method",path="$path"} $total',
      );
    }

    return buf.toString();
  }

  /// Clears all recorded metrics. Useful in tests.
  void reset() {
    _requestCounts.clear();
    _durationSums.clear();
    _durationCounts.clear();
    _histogramBuckets.clear();
  }
}

/// Records `http_requests_total` and `http_request_duration_seconds`
/// for every request passing through the pipeline.
///
/// Data is stored in [MetricsRegistry.instance] and exposed by
/// [MetricsController] at `GET /metrics`.
///
/// Enable automatically via `app.enableMetrics()`, or wire it manually:
/// ```dart
/// Pipeline()
///   .addMiddleware(metricsMiddleware())
///   .addHandler(router.handler.call)
/// ```
Middleware metricsMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      final sw = Stopwatch()..start();
      final response = await inner(request);
      sw.stop();
      MetricsRegistry.instance.recordRequest(
        request.method,
        request.requestedUri.path,
        response.statusCode,
        sw.elapsedMicroseconds / 1e6,
      );
      return response;
    };
  };
}
