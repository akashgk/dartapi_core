import 'dart:convert';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('ApiRoute - success responses', () {
    test('returns 200 by default', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.get,
        path: '/hello',
        typedHandler: (req, _) async => {'message': 'hello'},
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/hello')),
      );

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      expect(body, contains('hello'));
    });

    test('returns 201 when statusCode is 201', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.post,
        path: '/users',
        statusCode: 201,
        typedHandler: (req, _) async => {'id': '1'},
      );

      final response = await route.handler(
        Request('POST', Uri.parse('http://localhost/users')),
      );

      expect(response.statusCode, equals(201));
    });

    test('returns 204 when statusCode is 204', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.delete,
        path: '/items/1',
        statusCode: 204,
        typedHandler: (req, _) async => {},
      );

      final response = await route.handler(
        Request('DELETE', Uri.parse('http://localhost/items/1')),
      );

      expect(response.statusCode, equals(204));
    });

    test('response has application/json content-type', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.get,
        path: '/hello',
        typedHandler: (req, _) async => {'ok': 'true'},
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/hello')),
      );

      expect(response.headers['content-type'], contains('application/json'));
    });

    test('serializes List response', () async {
      final route = ApiRoute<void, List<String>>(
        method: ApiMethod.get,
        path: '/items',
        typedHandler: (req, _) async => ['a', 'b', 'c'],
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/items')),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body, equals(['a', 'b', 'c']));
    });

    test('serializes Serializable response', () async {
      final route = ApiRoute<void, _TestModel>(
        method: ApiMethod.get,
        path: '/model',
        typedHandler: (req, _) async => _TestModel('dart'),
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/model')),
      );

      final body = jsonDecode(await response.readAsString());
      expect(body['name'], equals('dart'));
    });

    test('serializes String response as plain text', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/text',
        typedHandler: (req, _) async => 'hello world',
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/text')),
      );

      expect(await response.readAsString(), equals('hello world'));
    });
  });

  group('ApiRoute - error handling', () {
    test('ApiException returns correct status code and message', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/secure',
        typedHandler: (req, _) async => throw ApiException(403, 'Forbidden'),
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/secure')),
      );

      expect(response.statusCode, equals(403));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('Forbidden'));
    });

    test('ApiException 404 returns correct body', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users/99',
        typedHandler: (req, _) async => throw ApiException(404, 'User not found'),
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/users/99')),
      );

      expect(response.statusCode, equals(404));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('User not found'));
    });

    test('FormatException returns 400 Bad Request', () async {
      final route = ApiRoute<Map<String, dynamic>, String>(
        method: ApiMethod.post,
        path: '/data',
        dtoParser: (json) => json,
        typedHandler: (req, dto) async => 'ok',
      );

      // Send malformed JSON body
      final response = await route.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/data'),
          body: '{invalid json',
        ),
      );

      expect(response.statusCode, equals(400));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('Bad Request'));
    });

    test('unhandled exception returns 500', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/crash',
        typedHandler: (req, _) async => throw Exception('unexpected'),
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/crash')),
      );

      expect(response.statusCode, equals(500));
      final body = jsonDecode(await response.readAsString());
      expect(body['error'], equals('Internal Server Error'));
    });

    test('unserializable response returns 500', () async {
      final route = ApiRoute<void, Object>(
        method: ApiMethod.get,
        path: '/bad',
        typedHandler: (req, _) async => Object(),
      );

      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/bad')),
      );

      expect(response.statusCode, equals(500));
      final body = await response.readAsString();
      expect(body, contains('Unable to serialize'));
    });
  });

  group('ApiRoute - per-route middleware', () {
    // Mirror how RouterManager applies middlewares to a route handler.
    Handler buildHandler(ApiRoute route) {
      Handler h = route.handler;
      for (final mw in route.middlewares) {
        h = mw(h);
      }
      return h;
    }

    test('middleware is applied before the handler', () async {
      final log = <String>[];

      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/mw',
        middlewares: [
          (inner) => (req) async {
                log.add('before');
                final res = await inner(req);
                log.add('after');
                return res;
              },
        ],
        typedHandler: (req, _) async {
          log.add('handler');
          return 'ok';
        },
      );

      await buildHandler(route)(Request('GET', Uri.parse('http://localhost/mw')));
      expect(log, equals(['before', 'handler', 'after']));
    });

    test('middleware can short-circuit and return early', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/guarded',
        middlewares: [
          (_) => (_) async => Response.forbidden('no access'),
        ],
        typedHandler: (req, _) async => 'should not reach',
      );

      final response = await buildHandler(route)(
        Request('GET', Uri.parse('http://localhost/guarded')),
      );
      expect(response.statusCode, equals(403));
      expect(await response.readAsString(), equals('no access'));
    });

    test('multiple middleware execute in order', () async {
      final log = <String>[];

      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/multi',
        middlewares: [
          (inner) => (req) async {
                log.add('mw1-in');
                final res = await inner(req);
                log.add('mw1-out');
                return res;
              },
          (inner) => (req) async {
                log.add('mw2-in');
                final res = await inner(req);
                log.add('mw2-out');
                return res;
              },
        ],
        typedHandler: (req, _) async {
          log.add('handler');
          return 'done';
        },
      );

      await buildHandler(route)(
        Request('GET', Uri.parse('http://localhost/multi')),
      );
      // Middlewares are wrapped in list order so the last one is outermost.
      // Execution: mw2 (outer) → mw1 (inner) → handler → mw1 → mw2.
      expect(log, equals(['mw2-in', 'mw1-in', 'handler', 'mw1-out', 'mw2-out']));
    });

    test('middleware can add response headers', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/headers',
        middlewares: [
          (inner) => (req) async {
                final res = await inner(req);
                return res.change(headers: {'x-custom': 'yes'});
              },
        ],
        typedHandler: (req, _) async => 'ok',
      );

      final response = await buildHandler(route)(
        Request('GET', Uri.parse('http://localhost/headers')),
      );
      expect(response.headers['x-custom'], equals('yes'));
    });
  });

  group('ApiRoute - dtoParser', () {
    test('parses request body and passes DTO to handler', () async {
      final route = ApiRoute<Map<String, dynamic>, String>(
        method: ApiMethod.post,
        path: '/echo',
        dtoParser: (json) => json,
        typedHandler: (req, dto) async => dto?['name'] as String? ?? 'empty',
      );

      final response = await route.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/echo'),
          body: '{"name":"dartapi"}',
        ),
      );

      expect(response.statusCode, equals(200));
      expect(await response.readAsString(), equals('dartapi'));
    });

    test('passes null DTO when no dtoParser is set', () async {
      String? captured;
      final route = ApiRoute<String, String>(
        method: ApiMethod.get,
        path: '/test',
        typedHandler: (req, dto) async {
          captured = dto;
          return 'ok';
        },
      );

      await route.handler(Request('GET', Uri.parse('http://localhost/test')));
      expect(captured, isNull);
    });
  });
}

class _TestModel implements Serializable {
  final String name;
  _TestModel(this.name);

  @override
  Map<String, dynamic> toJson() => {'name': name};
}
