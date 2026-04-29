import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('loggingMiddleware', () {
    Handler wrap(Handler inner) =>
        Pipeline().addMiddleware(loggingMiddleware()).addHandler(inner);

    test('passes request through to inner handler', () async {
      String? capturedMethod;
      final handler = wrap((req) async {
        capturedMethod = req.method;
        return Response.ok('ok');
      });

      await handler(Request('GET', Uri.parse('http://localhost/test')));
      expect(capturedMethod, equals('GET'));
    });

    test('returns the inner handler response unmodified', () async {
      final handler = wrap((_) async => Response(201, body: 'created'));

      final response = await handler(
        Request('POST', Uri.parse('http://localhost/items')),
      );
      expect(response.statusCode, equals(201));
      expect(await response.readAsString(), equals('created'));
    });

    test('does not swallow exceptions from inner handler', () async {
      final handler = wrap((_) async => throw Exception('boom'));

      expect(
        () => handler(Request('GET', Uri.parse('http://localhost/fail'))),
        throwsException,
      );
    });

    test('passes through all HTTP methods', () async {
      for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
        final handler = wrap((_) async => Response.ok(method));
        final response = await handler(
          Request(method, Uri.parse('http://localhost/resource')),
        );
        expect(response.statusCode, equals(200));
      }
    });

    test('works in a pipeline with other middleware', () async {
      final handler = Pipeline()
          .addMiddleware(loggingMiddleware())
          .addMiddleware(
            (inner) => (req) async {
              final res = await inner(req);
              return res.change(headers: {'x-extra': 'yes'});
            },
          )
          .addHandler((_) async => Response.ok('body'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/')),
      );
      expect(response.statusCode, equals(200));
      expect(response.headers['x-extra'], equals('yes'));
    });
  });
}
