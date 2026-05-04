import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('globalExceptionMiddleware', () {
    Handler buildHandler(Handler inner) {
      return globalExceptionMiddleware(
        onError: (error, _) {
          if (error is StateError) {
            return ApiException(503, 'Service unavailable');
          }
          return ApiException(500, 'Internal error');
        },
      )(inner);
    }

    test('passes through successful responses unchanged', () async {
      final handler = buildHandler((_) async => Response.ok('ok'));
      final req = Request('GET', Uri.parse('http://localhost/'));
      final res = await handler(req);
      expect(res.statusCode, equals(200));
    });

    test('intercepts StateError and returns 503', () async {
      final handler = buildHandler((_) async => throw StateError('down'));
      final req = Request('GET', Uri.parse('http://localhost/'));
      final res = await handler(req);
      expect(res.statusCode, equals(503));
      final body = await res.readAsString();
      expect(body, contains('Service unavailable'));
    });

    test('intercepts generic exception and returns 500', () async {
      final handler = buildHandler((_) async => throw Exception('boom'));
      final req = Request('GET', Uri.parse('http://localhost/'));
      final res = await handler(req);
      expect(res.statusCode, equals(500));
      final body = await res.readAsString();
      expect(body, contains('Internal error'));
    });

    test('response has JSON content type', () async {
      final handler = buildHandler((_) async => throw Exception('boom'));
      final req = Request('GET', Uri.parse('http://localhost/'));
      final res = await handler(req);
      expect(res.headers['content-type'], contains('application/json'));
    });
  });
}
