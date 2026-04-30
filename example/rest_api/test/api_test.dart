import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:rest_api/book_controller.dart';
import 'package:rest_api/dtos.dart';
import 'package:rest_api/repository.dart';
import 'package:test/test.dart';

JwtService _makeJwt() => JwtService(
      accessTokenSecret: 'test-secret',
      refreshTokenSecret: 'test-secret-refresh',
      issuer: 'test',
      audience: 'test-users',
    );

DartApiTestClient _buildClient(JwtService jwt) {
  final router = RouterManager();
  router.registerController(BookController(repo: BookRepository(), jwt: jwt));
  return DartApiTestClient(router.handler.call);
}

void main() {
  late DartApiTestClient client;
  late String token;

  setUp(() {
    final jwt = _makeJwt();
    client = _buildClient(jwt);
    token = jwt.generateAccessToken(claims: {'sub': '1'});
  });

  group('GET /books', () {
    test('returns paginated list', () async {
      final res = await client.get('/books');
      expect(res.statusCode, 200);
      final body = res.json<Map<String, dynamic>>();
      expect(body['data'], isA<List>());
      expect(body['meta'], isA<Map>());
    });

    test('respects page and limit query params', () async {
      final res = await client.get('/books?page=1&limit=1');
      expect(res.statusCode, 200);
      final data = res.json<Map<String, dynamic>>()['data'] as List;
      expect(data.length, 1);
    });
  });

  group('GET /books/<id>', () {
    test('returns a book', () async {
      final res = await client.get('/books/1');
      expect(res.statusCode, 200);
      expect(res.json<Map>()['id'], 1);
    });

    test('returns 404 for missing book', () async {
      final res = await client.get('/books/9999');
      expect(res.statusCode, 404);
    });
  });

  group('POST /books', () {
    test('creates a book and returns 201', () async {
      final res = await client.post(
        '/books',
        body: jsonEncode({'title': 'New Book', 'author': 'Author', 'year': 2024}),
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 201);
      final body = res.json<Map<String, dynamic>>();
      expect(body['title'], 'New Book');
      expect(body['id'], isNotNull);
    });

    test('returns 403 without auth', () async {
      final res = await client.post(
        '/books',
        body: jsonEncode({'title': 'X', 'author': 'Y', 'year': 2020}),
      );
      expect(res.statusCode, 403);
    });

    test('returns 422 for invalid DTO (empty title)', () async {
      final res = await client.post(
        '/books',
        body: jsonEncode({'title': '', 'author': 'Y', 'year': 2020}),
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 422);
    });
  });

  group('PUT /books/<id>', () {
    test('updates a book', () async {
      final res = await client.put(
        '/books/1',
        body: jsonEncode({'title': 'Updated', 'author': 'Author', 'year': 2020}),
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 200);
      expect(res.json<Map>()['title'], 'Updated');
    });

    test('returns 404 for missing book', () async {
      final res = await client.put(
        '/books/9999',
        body: jsonEncode({'title': 'X', 'author': 'Y', 'year': 2020}),
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 404);
    });
  });

  group('DELETE /books/<id>', () {
    test('deletes a book and returns 204', () async {
      final res = await client.delete(
        '/books/1',
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 204);
    });

    test('returns 404 for missing book', () async {
      final res = await client.delete(
        '/books/9999',
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 404);
    });
  });

  group('FieldSet schema', () {
    test('schema has type object', () {
      expect(BookDTO.schema['type'], 'object');
    });

    test('required fields are declared', () {
      expect(
        (BookDTO.schema['required'] as List),
        containsAll(['title', 'author', 'year']),
      );
    });

    test('year field has range constraint from RangeValidator', () {
      final props = BookDTO.schema['properties'] as Map;
      expect((props['year'] as Map)['minimum'], 1000);
      expect((props['year'] as Map)['maximum'], 2100);
    });
  });
}
