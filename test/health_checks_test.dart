import 'dart:convert';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request makeHealthReq() =>
    Request('GET', Uri.parse('http://localhost/health'));

void main() {
  group('HealthController with checks', () {
    test('no checks → status ok, no checks field', () async {
      final controller = HealthController();
      final res = await controller.routes.first.handler(makeHealthReq());
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('ok'));
      expect(body.containsKey('checks'), isFalse);
    });

    test('all checks healthy → status ok', () async {
      final controller = HealthController(
        checks: [
          () async => const HealthCheckResult(name: 'db', healthy: true),
          () async => const HealthCheckResult(name: 'cache', healthy: true),
        ],
      );
      final res = await controller.routes.first.handler(makeHealthReq());
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('ok'));
    });

    test('one unhealthy check → status degraded', () async {
      final controller = HealthController(
        checks: [
          () async => const HealthCheckResult(name: 'db', healthy: true),
          () async => const HealthCheckResult(
                name: 'cache',
                healthy: false,
                message: 'connection refused',
              ),
        ],
      );
      final res = await controller.routes.first.handler(makeHealthReq());
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['status'], equals('degraded'));
    });

    test('checks map includes each check result', () async {
      final controller = HealthController(
        checks: [
          () async => const HealthCheckResult(name: 'db', healthy: true),
          () async => const HealthCheckResult(
                name: 'stripe',
                healthy: false,
                message: 'timeout',
              ),
        ],
      );
      final res = await controller.routes.first.handler(makeHealthReq());
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final checks = body['checks'] as Map<String, dynamic>;
      expect((checks['db'] as Map)['healthy'], isTrue);
      expect((checks['stripe'] as Map)['healthy'], isFalse);
      expect((checks['stripe'] as Map)['message'], equals('timeout'));
    });

    test('healthy check has no message field', () async {
      final controller = HealthController(
        checks: [
          () async => const HealthCheckResult(name: 'db', healthy: true),
        ],
      );
      final res = await controller.routes.first.handler(makeHealthReq());
      final body =
          jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      final dbCheck = (body['checks'] as Map)['db'] as Map<String, dynamic>;
      expect(dbCheck.containsKey('message'), isFalse);
    });
  });
}
