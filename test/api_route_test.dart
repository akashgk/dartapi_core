import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('ApiRoute', () {
    test('can handle simple request and return JSON', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.get,
        path: '/hello',
        typedHandler: (Request req, _) async => {'message': 'hello'},
      );

      final request = Request('GET', Uri.parse('http://localhost/hello'));
      final response = await route.handler(request);

      expect(response.statusCode, equals(200));
      final body = await response.readAsString();
      expect(body, contains('hello'));
    });

    test('returns 201 when statusCode is set to 201', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.post,
        path: '/users',
        statusCode: 201,
        typedHandler: (Request req, _) async => {'id': '1'},
      );

      final request = Request('POST', Uri.parse('http://localhost/users'));
      final response = await route.handler(request);

      expect(response.statusCode, equals(201));
    });

    test('returns 204 when statusCode is set to 204', () async {
      final route = ApiRoute<void, Map<String, String>>(
        method: ApiMethod.delete,
        path: '/users/1',
        statusCode: 204,
        typedHandler: (Request req, _) async => {},
      );

      final request = Request('DELETE', Uri.parse('http://localhost/users/1'));
      final response = await route.handler(request);

      expect(response.statusCode, equals(204));
    });

    test('throws if serialization fails', () async {
      final route = ApiRoute<void, Object>(
        method: ApiMethod.get,
        path: '/bad',
        typedHandler: (Request req, _) async => Object(),
      );

      final request = Request('GET', Uri.parse('http://localhost/bad'));
      final response = await route.handler(request);

      expect(response.statusCode, equals(500));
      final body = await response.readAsString();
      expect(body, contains('Unable to serialize'));
    });
  });
}
