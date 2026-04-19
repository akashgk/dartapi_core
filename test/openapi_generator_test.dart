import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('OpenApiGenerator', () {
    test('produces correct openapi and info fields', () {
      final gen = OpenApiGenerator(
        routes: [],
        title: 'Test API',
        version: '2.0.0',
        description: 'A test API',
      );
      final spec = gen.generate();
      expect(spec['openapi'], equals('3.0.0'));
      expect(spec['info']['title'], equals('Test API'));
      expect(spec['info']['version'], equals('2.0.0'));
      expect(spec['info']['description'], equals('A test API'));
    });

    test('omits description from info when empty', () {
      final gen = OpenApiGenerator(routes: [], title: 'API');
      final spec = gen.generate();
      expect((spec['info'] as Map).containsKey('description'), isFalse);
    });

    test('registers GET route in paths', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        summary: 'List users',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      expect(spec['paths'], contains('/users'));
      expect(spec['paths']['/users'], contains('get'));
      expect(spec['paths']['/users']['get']['summary'], equals('List users'));
    });

    test('converts shelf_router path params to OpenAPI format', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users/<id>',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      expect(spec['paths'], contains('/users/{id}'));
      final params =
          spec['paths']['/users/{id}']['get']['parameters'] as List;
      expect(params.first['name'], equals('id'));
      expect(params.first['in'], equals('path'));
      expect(params.first['required'], isTrue);
    });

    test('includes multiple path params', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/orgs/<orgId>/users/<userId>',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final params =
          spec['paths']['/orgs/{orgId}/users/{userId}']['get']['parameters']
              as List;
      expect(params.map((p) => p['name']), containsAll(['orgId', 'userId']));
    });

    test('includes requestBody when requestSchema is set', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/users',
        requestSchema: {'type': 'object', 'properties': {'name': {'type': 'string'}}},
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final op = spec['paths']['/users']['post'];
      expect(op['requestBody']['required'], isTrue);
      expect(
        op['requestBody']['content']['application/json']['schema']['type'],
        equals('object'),
      );
    });

    test('includes response schema when responseSchema is set', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        statusCode: 200,
        responseSchema: {'type': 'array'},
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final response = spec['paths']['/users']['get']['responses']['200'];
      expect(response['content']['application/json']['schema']['type'],
          equals('array'));
    });

    test('uses correct status code key in responses', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/items',
        statusCode: 201,
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      expect(
        spec['paths']['/items']['post']['responses'],
        contains('201'),
      );
      expect(
        spec['paths']['/items']['post']['responses']['201']['description'],
        equals('Created'),
      );
    });

    test('adds bearer security scheme when route has security', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/me',
        security: [SecurityScheme.bearer],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final op = spec['paths']['/me']['get'];
      expect((op['security'] as List).any((s) => s is Map && s.containsKey('bearerAuth')), isTrue);
      expect(
        spec['components']['securitySchemes']['bearerAuth']['scheme'],
        equals('bearer'),
      );
    });

    test('always includes bearerAuth in components.securitySchemes', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/open',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final schemes =
          (spec['components'] as Map)['securitySchemes'] as Map;
      expect(schemes.containsKey('bearerAuth'), isTrue);
      expect((schemes['bearerAuth'] as Map)['scheme'], equals('bearer'));
    });

    test('toJson returns valid pretty-printed JSON', () {
      final gen = OpenApiGenerator(routes: [], title: 'API', version: '1.0.0');
      final json = gen.toJson();
      final decoded = jsonDecode(json);
      expect(decoded['openapi'], equals('3.0.0'));
    });

    test('multiple routes on the same path are grouped', () {
      final get = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/items',
        typedHandler: (req, _) async => 'ok',
      );
      final post = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/items',
        typedHandler: (req, _) async => 'ok',
      );
      final spec =
          OpenApiGenerator(routes: [get, post], title: 'API').generate();
      expect((spec['paths']['/items'] as Map).keys, containsAll(['get', 'post']));
    });
  });

  group('DocsController', () {
    test('exposes /openapi.json, /docs, /redoc routes', () {
      final controller = DocsController(apiRoutes: [], title: 'API');
      final paths = controller.routes.map((r) => r.path).toList();
      expect(paths, containsAll(['/openapi.json', '/docs', '/redoc']));
    });

    test('/openapi.json handler returns valid JSON', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/ping',
        summary: 'Ping',
        typedHandler: (req, _) async => 'pong',
      );
      final controller =
          DocsController(apiRoutes: [route], title: 'TestAPI', version: '3.0.0');
      final jsonRoute =
          controller.routes.firstWhere((r) => r.path == '/openapi.json');
      final result = await jsonRoute.typedHandler(
        // ignore: invalid_use_of_internal_member — test only
        // dart:shelf Request is needed; use the handler getter instead
        // We call typedHandler directly with a dummy Request.
        _dummyRequest(),
        null,
      );
      final decoded = jsonDecode(result);
      expect(decoded['info']['title'], equals('TestAPI'));
      expect(decoded['info']['version'], equals('3.0.0'));
      expect(decoded['paths'], contains('/ping'));
    });

    test('/docs route has text/html content type', () {
      final controller = DocsController(apiRoutes: [], title: 'API');
      final docsRoute =
          controller.routes.firstWhere((r) => r.path == '/docs');
      expect(docsRoute.contentType, equals('text/html'));
    });

    test('/redoc route has text/html content type', () {
      final controller = DocsController(apiRoutes: [], title: 'API');
      final redocRoute =
          controller.routes.firstWhere((r) => r.path == '/redoc');
      expect(redocRoute.contentType, equals('text/html'));
    });

    test('/docs handler returns HTML with swagger-ui', () async {
      final controller = DocsController(apiRoutes: [], title: 'MyDocs');
      final docsRoute =
          controller.routes.firstWhere((r) => r.path == '/docs');
      final html = await docsRoute.typedHandler(_dummyRequest(), null);
      expect(html, contains('swagger-ui'));
      expect(html, contains('MyDocs'));
    });

    test('/redoc handler returns HTML with redoc tag', () async {
      final controller = DocsController(apiRoutes: [], title: 'MyDocs');
      final redocRoute =
          controller.routes.firstWhere((r) => r.path == '/redoc');
      final html = await redocRoute.typedHandler(_dummyRequest(), null);
      expect(html, contains('<redoc'));
      expect(html, contains('MyDocs'));
    });
  });

  group('ApiRoute.security field', () {
    test('defaults to empty list', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/open',
        typedHandler: (req, _) async => 'ok',
      );
      expect(route.security, isEmpty);
    });

    test('accepts bearer scheme', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/secure',
        security: [SecurityScheme.bearer],
        typedHandler: (req, _) async => 'ok',
      );
      expect(route.security, contains(SecurityScheme.bearer));
    });
  });

  group('ApiRoute.contentType field', () {
    test('defaults to application/json', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/api',
        typedHandler: (req, _) async => 'ok',
      );
      expect(route.contentType, equals('application/json'));
    });

    test('can be set to text/html', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/page',
        contentType: 'text/html',
        typedHandler: (req, _) async => '<h1>hi</h1>',
      );
      expect(route.contentType, equals('text/html'));
    });

    test('response Content-Type header matches contentType field', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/page',
        contentType: 'text/html',
        typedHandler: (req, _) async => '<h1>hi</h1>',
      );
      final response = await route.handler(_dummyRequest());
      expect(response.headers['content-type'], equals('text/html'));
    });
  });
}

Request _dummyRequest() =>
    Request('GET', Uri.parse('http://localhost/test'));
