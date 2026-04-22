import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Future<Response> _echoHandler(Request request) async {
  final body = await request.readAsString();
  return Response.ok(
    jsonEncode({
      'method': request.method,
      'path': request.requestedUri.path,
      'body': body.isEmpty ? null : jsonDecode(body),
    }),
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late DartApiTestClient client;

  setUp(() {
    client = DartApiTestClient(_echoHandler);
  });

  group('DartApiTestClient', () {
    test('GET returns 200 and correct method/path', () async {
      final res = await client.get('/users');
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>();
      expect(data['method'], 'GET');
      expect(data['path'], '/users');
    });

    test('POST with body sends JSON', () async {
      final res = await client.post('/users', body: {'name': 'Alice'});
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>();
      expect(data['method'], 'POST');
      expect(data['body'], {'name': 'Alice'});
    });

    test('PUT with body', () async {
      final res = await client.put('/users/1', body: {'name': 'Bob'});
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>();
      expect(data['method'], 'PUT');
    });

    test('DELETE', () async {
      final res = await client.delete('/users/1');
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>();
      expect(data['method'], 'DELETE');
    });

    test('PATCH with body', () async {
      final res = await client.patch('/users/1', body: {'age': 30});
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>();
      expect(data['method'], 'PATCH');
    });

    test('defaultHeaders are sent on every request', () async {
      final authed = DartApiTestClient(
        (req) async => Response.ok(req.headers['authorization'] ?? 'none'),
        defaultHeaders: {'authorization': 'Bearer token123'},
      );
      final res = await authed.get('/protected');
      expect(res.body, 'Bearer token123');
    });

    test('per-request headers override defaultHeaders', () async {
      final authed = DartApiTestClient(
        (req) async => Response.ok(req.headers['authorization'] ?? 'none'),
        defaultHeaders: {'authorization': 'Bearer default'},
      );
      final res = await authed.get(
        '/protected',
        headers: {'authorization': 'Bearer override'},
      );
      expect(res.body, 'Bearer override');
    });

    test('json<T>() casts to Map', () async {
      final res = await client.get('/foo');
      expect(res.json<Map<String, dynamic>>(), isA<Map<String, dynamic>>());
    });
  });
}
