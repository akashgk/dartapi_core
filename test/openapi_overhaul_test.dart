import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

ApiRoute<void, String> _route(
  String path, {
  ApiMethod method = ApiMethod.get,
  List<SecurityScheme> security = const [],
  Map<int, ResponseSpec> responses = const {},
  String? operationId,
  List<PathParamSpec> pathParams = const [],
  FieldSet? requestFields,
}) => ApiRoute<void, String>(
  method: method,
  path: path,
  typedHandler: (req, _) async => 'ok',
  summary: path,
  security: security,
  responses: responses,
  operationId: operationId,
  pathParams: pathParams,
  requestFields: requestFields,
);

Map<String, dynamic> _spec(List<ApiRoute> routes) =>
    OpenApiGenerator(routes: routes, title: 'T').generate();

void main() {
  group('requestFields (FieldSet as single source of truth)', () {
    final fields = FieldSet({
      'name': Field<String>(validators: [NotEmptyValidator()]),
      'age': Field<int>(required: false),
    });

    test('request body schema is derived from the FieldSet', () {
      final spec = _spec([
        _route('/users', method: ApiMethod.post, requestFields: fields),
      ]);
      final body =
          spec['paths']['/users']['post']['requestBody']['content']['application/json']['schema']
              as Map<String, dynamic>;
      expect(body, equals(fields.toJsonSchema()));
    });

    test('explicit requestSchema wins over requestFields', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/users',
        typedHandler: (req, _) async => 'ok',
        requestFields: fields,
        requestSchema: {r'$ref': '#/components/schemas/X'},
      );
      expect(route.effectiveRequestSchema, {r'$ref': '#/components/schemas/X'});
    });

    test('routes with a body parser document 422 and 400 automatically', () {
      final spec = _spec([
        _route('/users', method: ApiMethod.post, requestFields: fields),
      ]);
      final responses =
          spec['paths']['/users']['post']['responses'] as Map<String, dynamic>;
      expect(responses.keys, containsAll(['200', '422', '400']));
      expect(
        responses['422']['content']['application/json']['schema'][r'$ref'],
        '#/components/schemas/ValidationError',
      );
      // The referenced schemas exist in components.
      final schemas = spec['components']['schemas'] as Map<String, dynamic>;
      expect(schemas.keys, containsAll(['ValidationError', 'Error']));
    });

    test('routes without a body parser have no auto error responses', () {
      final spec = _spec([_route('/plain')]);
      final responses =
          spec['paths']['/plain']['get']['responses'] as Map<String, dynamic>;
      expect(responses.keys, ['200']);
    });
  });

  group('security documentation', () {
    test('security routes document 401 automatically', () {
      final spec = _spec([
        _route('/me', security: [SecurityScheme.bearer]),
      ]);
      final responses =
          spec['paths']['/me']['get']['responses'] as Map<String, dynamic>;
      expect(responses.keys, containsAll(['200', '401']));
    });

    test('apiKey scheme maps to apiKeyAuth with configurable header', () {
      final spec =
          OpenApiGenerator(
            routes: [
              _route('/admin', security: [SecurityScheme.apiKey]),
            ],
            title: 'T',
            apiKeyHeader: 'X-Admin-Key',
          ).generate();
      expect(spec['paths']['/admin']['get']['security'], [
        {'apiKeyAuth': <String>[]},
      ]);
      final scheme = spec['components']['securitySchemes']['apiKeyAuth'];
      expect(scheme['type'], 'apiKey');
      expect(scheme['in'], 'header');
      expect(scheme['name'], 'X-Admin-Key');
    });
  });

  group('explicit responses', () {
    test('extra responses are documented', () {
      final spec = _spec([
        _route('/users/<id>', responses: {404: ResponseSpec('User not found')}),
      ]);
      final responses =
          spec['paths']['/users/{id}']['get']['responses']
              as Map<String, dynamic>;
      expect(responses['404']['description'], 'User not found');
    });

    test('explicit response overrides the automatic one', () {
      final fields = FieldSet({'name': Field<String>()});
      final spec = _spec([
        _route(
          '/users',
          method: ApiMethod.post,
          requestFields: fields,
          responses: {422: ResponseSpec('Custom validation docs')},
        ),
      ]);
      final r422 = spec['paths']['/users']['post']['responses']['422'];
      expect(r422['description'], 'Custom validation docs');
    });
  });

  group('operationId', () {
    test('derived from method and path', () {
      final spec = _spec([_route('/api/v1/users/<id>')]);
      expect(
        spec['paths']['/api/v1/users/{id}']['get']['operationId'],
        'get_api_v1_users_by_id',
      );
    });

    test('root path gets a stable id', () {
      final spec = _spec([_route('/')]);
      expect(spec['paths']['/']['get']['operationId'], 'get_root');
    });

    test('explicit operationId wins', () {
      final spec = _spec([_route('/users', operationId: 'listUsers')]);
      expect(spec['paths']['/users']['get']['operationId'], 'listUsers');
    });
  });

  group('typed path params', () {
    test('declared PathParamSpec controls the schema type', () {
      final spec = _spec([
        _route(
          '/users/<id>',
          pathParams: [
            PathParamSpec('id', type: 'integer', description: 'User id'),
          ],
        ),
      ]);
      final param = spec['paths']['/users/{id}']['get']['parameters'][0];
      expect(param['schema']['type'], 'integer');
      expect(param['description'], 'User id');
      expect(param['required'], isTrue);
    });

    test('undeclared path params fall back to string', () {
      final spec = _spec([_route('/users/<id>')]);
      final param = spec['paths']['/users/{id}']['get']['parameters'][0];
      expect(param['schema']['type'], 'string');
    });
  });

  group('servers', () {
    test('servers appear in the spec', () {
      final spec =
          OpenApiGenerator(
            routes: [_route('/x')],
            title: 'T',
            servers: ['https://api.example.com', 'http://localhost:8080'],
          ).generate();
      expect(spec['servers'], [
        {'url': 'https://api.example.com'},
        {'url': 'http://localhost:8080'},
      ]);
    });

    test('servers omitted when empty', () {
      expect(_spec([_route('/x')]).containsKey('servers'), isFalse);
    });
  });

  group('DocsController', () {
    test(
      'routes are read lazily — registration order no longer matters',
      () async {
        final router = RouterManager();
        // Docs registered FIRST…
        router.registerController(
          DocsController(
            routesProvider: () => router.collectedRoutes,
            title: 'T',
          ),
        );
        // …controller added afterwards still appears in the spec.
        router.registerController(InlineController([_route('/late')]));

        final client = DartApiTestClient(router.handler.call);
        final res = await client.get('/openapi.json');
        final paths = res.json<Map<String, dynamic>>()['paths'] as Map;
        expect(paths.containsKey('/late'), isTrue);
      },
    );

    test('docs endpoints are excluded from their own spec', () async {
      final router = RouterManager();
      router.registerController(
        DocsController(
          routesProvider: () => router.collectedRoutes,
          title: 'T',
        ),
      );
      final client = DartApiTestClient(router.handler.call);
      final res = await client.get('/openapi.json');
      final paths = res.json<Map<String, dynamic>>()['paths'] as Map;
      expect(paths.containsKey('/docs'), isFalse);
      expect(paths.containsKey('/openapi.json'), isFalse);
      expect(paths.containsKey('/redoc'), isFalse);
    });

    test('spec is generated once and cached', () async {
      var calls = 0;
      final controller = DocsController(
        routesProvider: () {
          calls++;
          return [_route('/x')];
        },
        title: 'T',
      );
      final router = RouterManager()..registerController(controller);
      final client = DartApiTestClient(router.handler.call);
      await client.get('/openapi.json');
      await client.get('/openapi.json');
      expect(calls, 1);
    });

    test(
      '/docs uses pinned asset versions (never @latest, never unpkg)',
      () async {
        final router =
            RouterManager()..registerController(
              DocsController(routesProvider: () => [], title: 'T'),
            );
        final client = DartApiTestClient(router.handler.call);
        final html = (await client.get('/docs')).body;
        expect(html, contains('swagger-ui-dist@$kSwaggerUiVersion'));
        expect(html, isNot(contains('@latest')));
        expect(html, isNot(contains('unpkg.com')));
        final redoc = (await client.get('/redoc')).body;
        expect(redoc, contains('redoc@$kRedocVersion'));
      },
    );

    test('asset URLs are overridable for self-hosting', () async {
      final router =
          RouterManager()..registerController(
            DocsController(
              routesProvider: () => [],
              title: 'T',
              swaggerUiCssUrl: '/assets/swagger-ui.css',
              swaggerUiJsUrl: '/assets/swagger-ui-bundle.js',
              redocJsUrl: '/assets/redoc.standalone.js',
            ),
          );
      final client = DartApiTestClient(router.handler.call);
      final html = (await client.get('/docs')).body;
      expect(html, contains('/assets/swagger-ui.css'));
      expect(html, contains('/assets/swagger-ui-bundle.js'));
      expect(html, isNot(contains('jsdelivr')));
    });
  });
}
