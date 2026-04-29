import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => MetricsRegistry.instance.reset());

  group('MetricsRegistry', () {
    test('records request count', () {
      MetricsRegistry.instance.recordRequest('GET', '/users', 200, 0.01);
      MetricsRegistry.instance.recordRequest('GET', '/users', 200, 0.02);
      final output = MetricsRegistry.instance.serialize();
      expect(
        output,
        contains(
          'http_requests_total{method="GET",path="/users",status="200"} 2',
        ),
      );
    });

    test('records different status codes separately', () {
      MetricsRegistry.instance.recordRequest('GET', '/users', 200, 0.01);
      MetricsRegistry.instance.recordRequest('GET', '/users', 404, 0.005);
      final output = MetricsRegistry.instance.serialize();
      expect(
        output,
        contains(
          'http_requests_total{method="GET",path="/users",status="200"} 1',
        ),
      );
      expect(
        output,
        contains(
          'http_requests_total{method="GET",path="/users",status="404"} 1',
        ),
      );
    });

    test('histogram +Inf bucket equals total count', () {
      MetricsRegistry.instance.recordRequest('POST', '/items', 201, 0.03);
      MetricsRegistry.instance.recordRequest('POST', '/items', 201, 0.07);
      final output = MetricsRegistry.instance.serialize();
      expect(
        output,
        contains(
          'http_request_duration_seconds_bucket{method="POST",path="/items",le="+Inf"} 2',
        ),
      );
    });

    test('fast request lands in tight buckets', () {
      MetricsRegistry.instance.recordRequest('GET', '/ping', 200, 0.003);
      final output = MetricsRegistry.instance.serialize();
      // 0.003s <= 0.005 bucket
      expect(
        output,
        contains(
          'http_request_duration_seconds_bucket{method="GET",path="/ping",le="0.005"} 1',
        ),
      );
    });

    test('slow request misses tight buckets', () {
      MetricsRegistry.instance.recordRequest('GET', '/slow', 200, 0.5);
      final output = MetricsRegistry.instance.serialize();
      // 0.5s > 0.1 bucket, should be 0
      expect(
        output,
        contains(
          'http_request_duration_seconds_bucket{method="GET",path="/slow",le="0.1"} 0',
        ),
      );
      // 0.5s <= 0.5 bucket, should be 1
      expect(
        output,
        contains(
          'http_request_duration_seconds_bucket{method="GET",path="/slow",le="0.5"} 1',
        ),
      );
    });

    test('serialize emits HELP and TYPE lines', () {
      MetricsRegistry.instance.recordRequest('GET', '/', 200, 0.01);
      final output = MetricsRegistry.instance.serialize();
      expect(output, contains('# HELP http_requests_total'));
      expect(output, contains('# TYPE http_requests_total counter'));
      expect(output, contains('# HELP http_request_duration_seconds'));
      expect(
        output,
        contains('# TYPE http_request_duration_seconds histogram'),
      );
    });

    test('reset clears all metrics', () {
      MetricsRegistry.instance.recordRequest('GET', '/users', 200, 0.01);
      MetricsRegistry.instance.reset();
      final output = MetricsRegistry.instance.serialize();
      expect(output, isNot(contains('http_requests_total{')));
    });
  });

  group('metricsMiddleware', () {
    test('records a request passing through the pipeline', () async {
      final handler = const Pipeline()
          .addMiddleware(metricsMiddleware())
          .addHandler((_) async => Response.ok('ok'));

      await handler(Request('GET', Uri.parse('http://localhost/test')));

      final output = MetricsRegistry.instance.serialize();
      expect(
        output,
        contains('http_requests_total{method="GET",path="/test",status="200"}'),
      );
    });
  });
}
