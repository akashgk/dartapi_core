import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('HealthController', () {
    final controller = HealthController();

    test('exposes GET /health route', () {
      expect(controller.routes, hasLength(1));
      expect(controller.routes.first.path, equals('/health'));
      expect(controller.routes.first.method, equals(ApiMethod.get));
    });

    test('GET /health returns 200', () async {
      final req = Request('GET', Uri.parse('http://localhost/health'));
      final res = await controller.routes.first.handler(req);
      expect(res.statusCode, equals(200));
    });

    test('GET /health returns JSON with status ok', () async {
      final req = Request('GET', Uri.parse('http://localhost/health'));
      final res = await controller.routes.first.handler(req);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('ok'));
    });

    test('GET /health returns uptime field', () async {
      final req = Request('GET', Uri.parse('http://localhost/health'));
      final res = await controller.routes.first.handler(req);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['uptime'], isA<String>());
      expect(body['uptime'], isNotEmpty);
    });
  });
}
