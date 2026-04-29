import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _req([String path = '/']) =>
    Request('GET', Uri.parse('http://localhost$path'));

void main() {
  group('timeoutMiddleware', () {
    test('fast handler completes normally', () async {
      final handler = Pipeline()
          .addMiddleware(timeoutMiddleware(const Duration(seconds: 5)))
          .addHandler((_) async => Response.ok('ok'));

      final res = await handler(_req());
      expect(res.statusCode, equals(200));
    });

    test('slow handler returns 408', () async {
      final handler = Pipeline()
          .addMiddleware(timeoutMiddleware(const Duration(milliseconds: 50)))
          .addHandler((_) async {
            await Future.delayed(const Duration(milliseconds: 200));
            return Response.ok('too late');
          });

      final res = await handler(_req());
      expect(res.statusCode, equals(408));
      final body = await res.readAsString();
      expect(body, contains('Request Timeout'));
    });

    test('408 response has JSON content-type', () async {
      final handler = Pipeline()
          .addMiddleware(timeoutMiddleware(const Duration(milliseconds: 50)))
          .addHandler((_) async {
            await Future.delayed(const Duration(milliseconds: 200));
            return Response.ok('too late');
          });

      final res = await handler(_req());
      expect(res.headers['content-type'], contains('application/json'));
    });
  });
}
