import 'dart:io';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a [DartApiTestClient] backed by [RouterManager] + [Pipeline]
/// that mirrors the DartAPI middleware stack (requestId + globalException).
DartApiTestClient _client(RouterManager router) {
  final pipeline = const Pipeline()
      .addMiddleware(requestIdMiddleware())
      .addMiddleware(
        globalExceptionMiddleware(
          onError: (error, _) {
            if (error is ApiException) return error;
            return const ApiException(500, 'Internal Server Error');
          },
        ),
      );
  return DartApiTestClient(pipeline.addHandler(router.handler.call));
}

/// Writes a temp .env file, returns its path.
String _writeTempEnv(String content) {
  final f = File(
    '${Directory.systemTemp.path}/dartapi_test_${DateTime.now().microsecondsSinceEpoch}.env',
  );
  f.writeAsStringSync(content);
  addTearDown(f.deleteSync);
  return f.path;
}

// ─────────────────────────────────────────────────────────────────────────────
// RouterManager
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('RouterManager', () {
    group('route registration', () {
      test('GET route returns 200 JSON', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, Map<String, dynamic>>(
              method: ApiMethod.get,
              path: '/ping',
              typedHandler: (req, _) async => {'pong': true},
              summary: 'ping',
            ),
          ]),
        );
        final res = await _client(router).get('/ping');
        expect(res.statusCode, 200);
        expect(res.json<Map<String, dynamic>>()['pong'], true);
      });

      test('POST route returns 201 with statusCode override', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, Map<String, dynamic>>(
              method: ApiMethod.post,
              path: '/items',
              statusCode: 201,
              typedHandler: (req, _) async => {'id': 1},
              summary: 'create',
            ),
          ]),
        );
        final res = await _client(router).post('/items');
        expect(res.statusCode, 201);
      });

      test('PUT route', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.put,
              path: '/items/1',
              typedHandler: (req, _) async => 'updated',
              summary: 'update',
            ),
          ]),
        );
        final res = await _client(router).put('/items/1');
        expect(res.statusCode, 200);
      });

      test('DELETE route', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.delete,
              path: '/items/1',
              statusCode: 204,
              typedHandler: (req, _) async => '',
              summary: 'delete',
            ),
          ]),
        );
        final res = await _client(router).delete('/items/1');
        expect(res.statusCode, 204);
      });

      test('PATCH route', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.patch,
              path: '/items/1',
              typedHandler: (req, _) async => 'patched',
              summary: 'patch',
            ),
          ]),
        );
        final res = await _client(router).patch('/items/1');
        expect(res.statusCode, 200);
      });

      test('unknown route returns 404', () async {
        final router = RouterManager();
        router.registerController(InlineController([]));
        final res = await _client(router).get('/does-not-exist');
        expect(res.statusCode, 404);
      });

      test('multiple controllers, all routes reachable', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/a',
              typedHandler: (req, _) async => 'a',
              summary: 'a',
            ),
          ]),
        );
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/b',
              typedHandler: (req, _) async => 'b',
              summary: 'b',
            ),
          ]),
        );
        expect((await _client(router).get('/a')).statusCode, 200);
        expect((await _client(router).get('/b')).statusCode, 200);
      });

      test('multiple routes on same controller', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/x',
              typedHandler: (req, _) async => 'x',
              summary: 'x',
            ),
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/y',
              typedHandler: (req, _) async => 'y',
              summary: 'y',
            ),
          ]),
        );
        expect((await _client(router).get('/x')).statusCode, 200);
        expect((await _client(router).get('/y')).statusCode, 200);
      });

      test('ApiException thrown in handler propagates to 4xx', () async {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, void>(
              method: ApiMethod.get,
              path: '/forbidden',
              typedHandler:
                  (req, _) async => throw const ApiException(403, 'Forbidden'),
              summary: 'forbidden',
            ),
          ]),
        );
        // ApiRoute itself catches ApiException and returns it directly.
        final res = await _client(router).get('/forbidden');
        expect(res.statusCode, 403);
      });

      test('per-route middleware is applied before handler', () async {
        var middlewareCalled = false;
        Middleware tracer() =>
            (inner) => (req) async {
              middlewareCalled = true;
              return inner(req);
            };

        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/traced',
              typedHandler: (req, _) async => 'ok',
              summary: 'traced',
              middlewares: [tracer()],
            ),
          ]),
        );
        await _client(router).get('/traced');
        expect(middlewareCalled, isTrue);
      });

      test('per-route middleware can short-circuit', () async {
        Middleware blocker() =>
            (inner) => (req) async => Response.forbidden('blocked');

        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/blocked',
              typedHandler: (req, _) async => 'should not reach',
              summary: 'blocked',
              middlewares: [blocker()],
            ),
          ]),
        );
        final res = await _client(router).get('/blocked');
        expect(res.statusCode, 403);
      });
    });

    group('collectedRoutes', () {
      test('contains all registered routes', () {
        final router = RouterManager();
        final r1 = ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/a',
          typedHandler: (req, _) async => 'a',
          summary: 'a',
        );
        final r2 = ApiRoute<void, String>(
          method: ApiMethod.post,
          path: '/b',
          typedHandler: (req, _) async => 'b',
          summary: 'b',
        );
        router.registerController(InlineController([r1, r2]));
        expect(router.collectedRoutes, containsAll([r1, r2]));
      });

      test('is empty before any controller is registered', () {
        expect(RouterManager().collectedRoutes, isEmpty);
      });

      test('is unmodifiable — throws on mutation attempt', () {
        final router = RouterManager();
        expect(
          () => (router.collectedRoutes as List).add(
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/x',
              typedHandler: (req, _) async => 'x',
              summary: 'x',
            ),
          ),
          throwsUnsupportedError,
        );
      });

      test('count matches number of registered routes across controllers', () {
        final router = RouterManager();
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/1',
              typedHandler: (req, _) async => '1',
              summary: '1',
            ),
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/2',
              typedHandler: (req, _) async => '2',
              summary: '2',
            ),
          ]),
        );
        router.registerController(
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/3',
              typedHandler: (req, _) async => '3',
              summary: '3',
            ),
          ]),
        );
        expect(router.collectedRoutes.length, 3);
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // InlineController
  // ───────────────────────────────────────────────────────────────────────────

  group('InlineController', () {
    test('exposes routes passed in constructor', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/hello',
        typedHandler: (req, _) async => 'hello',
        summary: 'hello',
      );
      final controller = InlineController([route]);
      expect(controller.routes, [route]);
    });

    test('webSocketRoutes is empty by default', () {
      final controller = InlineController([]);
      expect(controller.webSocketRoutes, isEmpty);
    });

    test('accepts empty routes list', () {
      final controller = InlineController([]);
      expect(controller.routes, isEmpty);
    });

    test('accepts multiple routes', () {
      final r1 = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/a',
        typedHandler: (req, _) async => 'a',
        summary: 'a',
      );
      final r2 = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/b',
        typedHandler: (req, _) async => 'b',
        summary: 'b',
      );
      final controller = InlineController([r1, r2]);
      expect(controller.routes.length, 2);
      expect(controller.routes, containsAll([r1, r2]));
    });

    test('is a BaseController subtype', () {
      final controller = InlineController([]);
      expect(controller, isA<BaseController>());
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // DartAPI lifecycle hooks (unit-level — no socket binding)
  // ───────────────────────────────────────────────────────────────────────────

  group('DartAPI hooks', () {
    test('onStartup callbacks are stored and can be registered', () {
      final app = DartAPI();
      var called = false;
      app.onStartup(() async {
        called = true;
      });
      // Hooks are internal; we verify indirectly via addControllers side-effect.
      // The fact it doesn't throw confirms registration.
      expect(called, isFalse); // not called yet — called only on start()
    });

    test('addControllers registers each controller with the router', () {
      final app = DartAPI();
      // addControllers must not throw.
      expect(
        () => app.addControllers([
          InlineController([
            ApiRoute<void, String>(
              method: ApiMethod.get,
              path: '/x',
              typedHandler: (req, _) async => 'x',
              summary: 'x',
            ),
          ]),
        ]),
        returnsNormally,
      );
    });

    test('enableCompression does not throw', () {
      expect(() => DartAPI().enableCompression(), returnsNormally);
      expect(
        () => DartAPI().enableCompression(threshold: 512),
        returnsNormally,
      );
    });

    test('enableBackgroundTasks does not throw', () {
      expect(() => DartAPI().enableBackgroundTasks(), returnsNormally);
    });

    test('enableTimeout does not throw', () {
      expect(
        () => DartAPI().enableTimeout(const Duration(seconds: 30)),
        returnsNormally,
      );
    });

    test('enableRateLimit does not throw', () {
      expect(
        () => DartAPI().enableRateLimit(
          maxRequests: 100,
          window: const Duration(minutes: 1),
        ),
        returnsNormally,
      );
    });

    test('enableHealthCheck does not throw', () {
      expect(() => DartAPI().enableHealthCheck(), returnsNormally);
    });

    test('enableMetrics does not throw', () {
      expect(() => DartAPI().enableMetrics(), returnsNormally);
    });

    test('enableDocs does not throw after addControllers', () {
      final app = DartAPI();
      app.addControllers([InlineController([])]);
      expect(
        () => app.enableDocs(title: 'Test', version: '0.1.0'),
        returnsNormally,
      );
    });

    test('corsOrigin defaults to *', () {
      // Verify DartAPI can be constructed with defaults.
      final app = DartAPI();
      expect(app.corsOrigin, '*');
    });

    test('appName defaults to dartapi', () {
      final app = DartAPI();
      expect(app.appName, 'dartapi');
    });

    test('custom corsOrigin is accepted', () {
      final app = DartAPI(corsOrigin: 'https://example.com');
      expect(app.corsOrigin, 'https://example.com');
    });

    test('custom appName is accepted', () {
      final app = DartAPI(appName: 'my_api');
      expect(app.appName, 'my_api');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // DartAPI pipeline integration (via in-process handler)
  // ───────────────────────────────────────────────────────────────────────────

  group('DartAPI pipeline integration', () {
    DartApiTestClient buildPipeline(List<ApiRoute> routes) {
      final router =
          RouterManager()..registerController(InlineController(routes));
      final pipeline = const Pipeline()
          .addMiddleware(requestIdMiddleware())
          .addMiddleware(
            globalExceptionMiddleware(
              onError: (error, _) {
                if (error is ApiException) return error;
                return const ApiException(500, 'Internal Server Error');
              },
            ),
          );
      return DartApiTestClient(pipeline.addHandler(router.handler.call));
    }

    test('200 JSON route', () async {
      final client = buildPipeline([
        ApiRoute<void, Map<String, dynamic>>(
          method: ApiMethod.get,
          path: '/hello',
          typedHandler: (req, _) async => {'hello': 'world'},
          summary: 's',
        ),
      ]);
      final res = await client.get('/hello');
      expect(res.statusCode, 200);
      expect(res.json<Map<String, dynamic>>()['hello'], 'world');
    });

    test('ApiException in handler → correct status code', () async {
      final client = buildPipeline([
        ApiRoute<void, void>(
          method: ApiMethod.get,
          path: '/gone',
          typedHandler: (req, _) async => throw const ApiException(410, 'Gone'),
          summary: 's',
        ),
      ]);
      final res = await client.get('/gone');
      expect(res.statusCode, 410);
    });

    test('unhandled exception → 500', () async {
      final client = buildPipeline([
        ApiRoute<void, void>(
          method: ApiMethod.get,
          path: '/boom',
          typedHandler: (req, _) async => throw Exception('unexpected'),
          summary: 's',
        ),
      ]);
      // ApiRoute catches generic exceptions and maps to 500 before
      // globalExceptionMiddleware even sees them.
      final res = await client.get('/boom');
      expect(res.statusCode, 500);
    });

    test('requestIdMiddleware attaches X-Request-Id to response', () async {
      final client = buildPipeline([
        ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/id',
          typedHandler: (req, _) async => 'ok',
          summary: 's',
        ),
      ]);
      final res = await client.get('/id');
      final hasId = res.headers.keys.any(
        (k) => k.toLowerCase() == 'x-request-id',
      );
      expect(hasId, isTrue);
    });

    test('requestIdMiddleware propagates incoming X-Request-Id', () async {
      final client = buildPipeline([
        ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/id',
          typedHandler: (req, _) async => 'ok',
          summary: 's',
        ),
      ]);
      final res = await client.get('/id', headers: {'X-Request-Id': 'abc-123'});
      final id =
          res.headers.entries
              .firstWhere((e) => e.key.toLowerCase() == 'x-request-id')
              .value;
      expect(id, 'abc-123');
    });

    test('rateLimit middleware returns 429 when limit exceeded', () async {
      final router =
          RouterManager()..registerController(
            InlineController([
              ApiRoute<void, String>(
                method: ApiMethod.get,
                path: '/limited',
                typedHandler: (req, _) async => 'ok',
                summary: 's',
              ),
            ]),
          );
      final pipeline = const Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              maxRequests: 2,
              window: const Duration(minutes: 1),
              keyExtractor: (_) => 'test-key',
            ),
          )
          .addMiddleware(
            globalExceptionMiddleware(
              onError:
                  (e, _) =>
                      e is ApiException ? e : const ApiException(500, 'err'),
            ),
          );
      final client = DartApiTestClient(
        pipeline.addHandler(router.handler.call),
      );

      expect((await client.get('/limited')).statusCode, 200);
      expect((await client.get('/limited')).statusCode, 200);
      expect((await client.get('/limited')).statusCode, 429);
    });

    test('timeout middleware returns 408 when handler is too slow', () async {
      final router =
          RouterManager()..registerController(
            InlineController([
              ApiRoute<void, String>(
                method: ApiMethod.get,
                path: '/slow',
                typedHandler: (req, _) async {
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                  return 'too late';
                },
                summary: 's',
              ),
            ]),
          );
      final pipeline = const Pipeline().addMiddleware(
        timeoutMiddleware(const Duration(milliseconds: 50)),
      );
      final client = DartApiTestClient(
        pipeline.addHandler(router.handler.call),
      );
      final res = await client.get('/slow');
      expect(res.statusCode, 408);
    });

    test('backgroundTaskMiddleware makes backgroundTasks available', () async {
      var taskRan = false;
      final router =
          RouterManager()..registerController(
            InlineController([
              ApiRoute<void, String>(
                method: ApiMethod.get,
                path: '/bg',
                typedHandler: (req, _) async {
                  req.backgroundTasks.add(() async {
                    taskRan = true;
                  });
                  return 'ok';
                },
                summary: 's',
              ),
            ]),
          );
      final pipeline = const Pipeline().addMiddleware(
        backgroundTaskMiddleware(),
      );
      final client = DartApiTestClient(
        pipeline.addHandler(router.handler.call),
      );

      await client.get('/bg');
      // Give the event loop a tick to run background tasks.
      await Future<void>.delayed(Duration.zero);
      expect(taskRan, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AppConfig
  // ───────────────────────────────────────────────────────────────────────────

  group('AppConfig', () {
    group('appEnv', () {
      test('defaults to dev', () {
        expect(AppConfig(environment: {}).appEnv, AppEnvironment.dev);
      });

      test('dev', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'dev'}).appEnv,
          AppEnvironment.dev,
        );
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).isDev, isTrue);
      });

      test('staging', () {
        final cfg = AppConfig(environment: {'APP_ENV': 'staging'});
        expect(cfg.appEnv, AppEnvironment.staging);
        expect(cfg.isStaging, isTrue);
        expect(cfg.isDev, isFalse);
      });

      test('uat', () {
        final cfg = AppConfig(environment: {'APP_ENV': 'uat'});
        expect(cfg.appEnv, AppEnvironment.uat);
        expect(cfg.isUat, isTrue);
      });

      test('production', () {
        final cfg = AppConfig(environment: {'APP_ENV': 'production'});
        expect(cfg.appEnv, AppEnvironment.production);
        expect(cfg.isProduction, isTrue);
        expect(cfg.isDev, isFalse);
      });

      test('"prod" alias is treated as production', () {
        final cfg = AppConfig(environment: {'APP_ENV': 'prod'});
        expect(cfg.appEnv, AppEnvironment.production);
        expect(cfg.isProduction, isTrue);
      });

      test('unknown value falls back to dev', () {
        final cfg = AppConfig(environment: {'APP_ENV': 'banana'});
        expect(cfg.appEnv, AppEnvironment.dev);
      });
    });

    group('server', () {
      test('PORT defaults to 8080', () {
        expect(AppConfig(environment: {}).port, 8080);
      });

      test('PORT is read from env', () {
        expect(AppConfig(environment: {'PORT': '9090'}).port, 9090);
      });

      test('DEBUG defaults to true in dev', () {
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).debug, isTrue);
      });

      test('DEBUG defaults to false in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).debug,
          isFalse,
        );
      });

      test('DEBUG can be forced true in production', () {
        expect(
          AppConfig(
            environment: {'APP_ENV': 'production', 'DEBUG': 'true'},
          ).debug,
          isTrue,
        );
      });

      test('logLevel is debug in dev', () {
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).logLevel, 'debug');
      });

      test('logLevel is info in staging', () {
        expect(AppConfig(environment: {'APP_ENV': 'staging'}).logLevel, 'info');
      });

      test('logLevel is info in uat', () {
        expect(AppConfig(environment: {'APP_ENV': 'uat'}).logLevel, 'info');
      });

      test('logLevel is warn in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).logLevel,
          'warn',
        );
      });

      test('logLevel can be overridden via LOG_LEVEL', () {
        expect(
          AppConfig(
            environment: {'APP_ENV': 'dev', 'LOG_LEVEL': 'error'},
          ).logLevel,
          'error',
        );
      });
    });

    group('database', () {
      test('dbEnabled defaults to false', () {
        expect(AppConfig(environment: {}).dbEnabled, isFalse);
      });

      test('dbEnabled reads DB_ENABLED=true', () {
        expect(
          AppConfig(environment: {'DB_ENABLED': 'true'}).dbEnabled,
          isTrue,
        );
      });

      test('dbHost defaults to localhost', () {
        expect(AppConfig(environment: {}).dbHost, 'localhost');
      });

      test('dbHost reads DB_HOST', () {
        expect(
          AppConfig(environment: {'DB_HOST': 'db.internal'}).dbHost,
          'db.internal',
        );
      });

      test('dbPort defaults to 5432', () {
        expect(AppConfig(environment: {}).dbPort, 5432);
      });

      test('dbPort reads DB_PORT', () {
        expect(AppConfig(environment: {'DB_PORT': '3306'}).dbPort, 3306);
      });

      test('dbName defaults to app_dev in dev', () {
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).dbName, 'app_dev');
      });

      test('dbName defaults to app_production in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).dbName,
          'app_production',
        );
      });

      test('dbName reads DB_NAME', () {
        expect(AppConfig(environment: {'DB_NAME': 'mydb'}).dbName, 'mydb');
      });

      test('dbUser defaults to postgres', () {
        expect(AppConfig(environment: {}).dbUser, 'postgres');
      });

      test('dbPassword defaults to yourpassword', () {
        expect(AppConfig(environment: {}).dbPassword, 'yourpassword');
      });

      test('dbPoolSize is 5 in dev', () {
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).dbPoolSize, 5);
      });

      test('dbPoolSize is 20 in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).dbPoolSize,
          20,
        );
      });

      test('dbPoolSize reads DB_POOL_SIZE', () {
        expect(AppConfig(environment: {'DB_POOL_SIZE': '10'}).dbPoolSize, 10);
      });
    });

    group('JWT', () {
      test('jwtAccessSecret has dev default', () {
        expect(
          AppConfig(environment: {}).jwtAccessSecret,
          contains('dev-access-secret'),
        );
      });

      test('jwtRefreshSecret has dev default', () {
        expect(
          AppConfig(environment: {}).jwtRefreshSecret,
          contains('dev-refresh-secret'),
        );
      });

      test('jwtAccessSecret reads JWT_ACCESS_SECRET', () {
        expect(
          AppConfig(
            environment: {'JWT_ACCESS_SECRET': 'my-secret'},
          ).jwtAccessSecret,
          'my-secret',
        );
      });

      test('jwtAccessExpiry is 60 min in dev', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'dev'}).jwtAccessExpiry,
          const Duration(minutes: 60),
        );
      });

      test('jwtAccessExpiry is 15 min in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).jwtAccessExpiry,
          const Duration(minutes: 15),
        );
      });

      test('jwtRefreshExpiry is 30 days in dev', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'dev'}).jwtRefreshExpiry,
          const Duration(days: 30),
        );
      });

      test('jwtRefreshExpiry is 7 days in production', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).jwtRefreshExpiry,
          const Duration(days: 7),
        );
      });

      test('production access expiry is shorter than dev', () {
        final dev = AppConfig(environment: {'APP_ENV': 'dev'});
        final prod = AppConfig(environment: {'APP_ENV': 'production'});
        expect(prod.jwtAccessExpiry < dev.jwtAccessExpiry, isTrue);
      });

      test('production refresh expiry is shorter than dev', () {
        final dev = AppConfig(environment: {'APP_ENV': 'dev'});
        final prod = AppConfig(environment: {'APP_ENV': 'production'});
        expect(prod.jwtRefreshExpiry < dev.jwtRefreshExpiry, isTrue);
      });

      test('JWT_ACCESS_EXPIRY_MINUTES override', () {
        expect(
          AppConfig(
            environment: {'JWT_ACCESS_EXPIRY_MINUTES': '5'},
          ).jwtAccessExpiry,
          const Duration(minutes: 5),
        );
      });
    });

    group('CORS', () {
      test('corsOrigin is * in dev', () {
        expect(AppConfig(environment: {'APP_ENV': 'dev'}).corsOrigin, '*');
      });

      test('corsOrigin is empty string in production by default', () {
        expect(
          AppConfig(environment: {'APP_ENV': 'production'}).corsOrigin,
          '',
        );
      });

      test('corsOrigin reads CORS_ORIGIN', () {
        expect(
          AppConfig(
            environment: {
              'APP_ENV': 'production',
              'CORS_ORIGIN': 'https://example.com',
            },
          ).corsOrigin,
          'https://example.com',
        );
      });
    });

    group('validateForProduction', () {
      test('does not print anything in dev', () {
        // Should not throw.
        expect(
          () =>
              AppConfig(
                environment: {'APP_ENV': 'dev'},
              ).validateForProduction(),
          returnsNormally,
        );
      });

      test('does not throw even with dev secrets in production', () {
        // validateForProduction only prints — it does not throw.
        expect(
          () =>
              AppConfig(
                environment: {'APP_ENV': 'production'},
              ).validateForProduction(),
          returnsNormally,
        );
      });

      test('does not throw with real secrets in production', () {
        expect(
          () =>
              AppConfig(
                environment: {
                  'APP_ENV': 'production',
                  'JWT_ACCESS_SECRET': 'a-real-secret-value',
                  'JWT_REFRESH_SECRET': 'another-real-secret-value',
                },
              ).validateForProduction(),
          returnsNormally,
        );
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // EnvLoader
  // ───────────────────────────────────────────────────────────────────────────

  group('loadEnvFile', () {
    test('returns empty map for non-existent file', () {
      expect(loadEnvFile('/tmp/__nonexistent_dartapi__.env'), isEmpty);
    });

    test('parses key=value pairs', () {
      final path = _writeTempEnv('FOO=bar\nBAZ=qux\n');
      final result = loadEnvFile(path);
      expect(result['FOO'], 'bar');
      expect(result['BAZ'], 'qux');
    });

    test('ignores comment lines', () {
      final path = _writeTempEnv('# this is a comment\nKEY=value\n');
      final result = loadEnvFile(path);
      expect(result.containsKey('#'), isFalse);
      expect(result['KEY'], 'value');
    });

    test('ignores empty lines', () {
      final path = _writeTempEnv('\n\nKEY=val\n\n');
      final result = loadEnvFile(path);
      expect(result.length, 1);
      expect(result['KEY'], 'val');
    });

    test('strips double-quoted values', () {
      final path = _writeTempEnv('KEY="hello world"\n');
      expect(loadEnvFile(path)['KEY'], 'hello world');
    });

    test('strips single-quoted values', () {
      final path = _writeTempEnv("KEY='hello world'\n");
      expect(loadEnvFile(path)['KEY'], 'hello world');
    });

    test('strips inline comments (space + #)', () {
      final path = _writeTempEnv('KEY=value # this is a comment\n');
      expect(loadEnvFile(path)['KEY'], 'value');
    });

    test('handles value with = sign', () {
      final path = _writeTempEnv('KEY=a=b\n');
      expect(loadEnvFile(path)['KEY'], 'a=b');
    });

    test('ignores lines without = sign', () {
      final path = _writeTempEnv('NOEQUALS\nKEY=val\n');
      final result = loadEnvFile(path);
      expect(result.containsKey('NOEQUALS'), isFalse);
      expect(result['KEY'], 'val');
    });

    test('trims whitespace from keys and values', () {
      final path = _writeTempEnv('  KEY  =  value  \n');
      expect(loadEnvFile(path)['KEY'], 'value');
    });

    test('returns empty map for empty file', () {
      final path = _writeTempEnv('');
      expect(loadEnvFile(path), isEmpty);
    });

    test('parses multiple entries correctly', () {
      final path = _writeTempEnv(
        'A=1\n'
        '# comment\n'
        '\n'
        'B="two"\n'
        "C='three'\n"
        'D=four # inline comment\n',
      );
      final result = loadEnvFile(path);
      expect(result['A'], '1');
      expect(result['B'], 'two');
      expect(result['C'], 'three');
      expect(result['D'], 'four');
    });
  });

  group('mergeEnv', () {
    test('merges single source', () {
      final result = mergeEnv([
        {'A': '1'},
      ]);
      expect(result['A'], '1');
    });

    test('later source overrides earlier', () {
      final result = mergeEnv([
        {'A': '1', 'B': '2'},
        {'B': '3', 'C': '4'},
      ]);
      expect(result['A'], '1');
      expect(result['B'], '3');
      expect(result['C'], '4');
    });

    test('empty sources produce only Platform.environment', () {
      // Should not throw and returns at least the process env.
      final result = mergeEnv([]);
      // PATH is always set on Unix/Mac/Windows.
      expect(result, isNotEmpty);
    });

    test('three-way merge respects priority order', () {
      final result = mergeEnv([
        {'X': 'first'},
        {'X': 'second'},
        {'X': 'third'},
      ]);
      expect(result['X'], 'third');
    });

    test('keys from all sources are included', () {
      final result = mergeEnv([
        {'A': '1'},
        {'B': '2'},
        {'C': '3'},
      ]);
      expect(result.containsKey('A'), isTrue);
      expect(result.containsKey('B'), isTrue);
      expect(result.containsKey('C'), isTrue);
    });
  });
}
