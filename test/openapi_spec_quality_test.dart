import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  // ── QueryParamSpec ────────────────────────────────────────────────────────

  group('QueryParamSpec', () {
    test('defaults to string type and not required', () {
      final qp = QueryParamSpec('q');
      final param = qp.toOpenApiParameter();
      expect(param['name'], 'q');
      expect(param['in'], 'query');
      expect(param['required'], isFalse);
      expect((param['schema'] as Map)['type'], 'string');
    });

    test('required flag is emitted', () {
      final qp = QueryParamSpec('token', required: true);
      expect(qp.toOpenApiParameter()['required'], isTrue);
    });

    test('integer type is emitted', () {
      final qp = QueryParamSpec('page', type: 'integer', defaultValue: 1);
      final param = qp.toOpenApiParameter();
      expect((param['schema'] as Map)['type'], 'integer');
      expect((param['schema'] as Map)['default'], 1);
    });

    test('description appears when set', () {
      final qp = QueryParamSpec('search', description: 'Filter by name');
      final param = qp.toOpenApiParameter();
      expect(param['description'], 'Filter by name');
    });

    test('no description key when not set', () {
      final qp = QueryParamSpec('page');
      expect(qp.toOpenApiParameter().containsKey('description'), isFalse);
    });

    test('no default key when not set', () {
      final qp = QueryParamSpec('page');
      expect(
        (qp.toOpenApiParameter()['schema'] as Map).containsKey('default'),
        isFalse,
      );
    });
  });

  // ── OpenApiGenerator — query params ───────────────────────────────────────

  group('OpenApiGenerator query params', () {
    ApiRoute<void, String> makeRoute({List<QueryParamSpec> qp = const []}) =>
        ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/items',
          queryParams: qp,
          typedHandler: (req, _) async => 'ok',
        );

    test('query params appear under parameters with in: query', () {
      final spec =
          OpenApiGenerator(
            routes: [
              makeRoute(
                qp: [
                  QueryParamSpec('page', type: 'integer', defaultValue: 1),
                  QueryParamSpec('limit', type: 'integer', defaultValue: 20),
                ],
              ),
            ],
            title: 'API',
          ).generate();

      final params = spec['paths']['/items']['get']['parameters'] as List;
      final names = params.map((p) => p['name']).toList();
      expect(names, containsAll(['page', 'limit']));

      final page = params.firstWhere((p) => p['name'] == 'page');
      expect(page['in'], 'query');
      expect((page['schema'] as Map)['type'], 'integer');
      expect((page['schema'] as Map)['default'], 1);
    });

    test('path params and query params are both included', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users/<id>',
        queryParams: [QueryParamSpec('verbose', type: 'boolean')],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final params = spec['paths']['/users/{id}']['get']['parameters'] as List;
      final inValues = params.map((p) => p['in']).toList();
      expect(inValues, containsAll(['path', 'query']));
    });

    test('no parameters key when route has no path or query params', () {
      final spec =
          OpenApiGenerator(routes: [makeRoute()], title: 'API').generate();
      expect(
        (spec['paths']['/items']['get'] as Map).containsKey('parameters'),
        isFalse,
      );
    });

    test('required query param is marked required', () {
      final spec =
          OpenApiGenerator(
            routes: [
              makeRoute(qp: [QueryParamSpec('token', required: true)]),
            ],
            title: 'API',
          ).generate();
      final params = spec['paths']['/items']['get']['parameters'] as List;
      final token = params.firstWhere((p) => p['name'] == 'token');
      expect(token['required'], isTrue);
    });
  });

  // ── OpenApiGenerator — components/schemas ─────────────────────────────────

  group('OpenApiGenerator components/schemas', () {
    test('schemas map appears under components.schemas', () {
      final spec =
          OpenApiGenerator(
            routes: [],
            title: 'API',
            schemas: {
              'CreateUserDTO': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                },
              },
            },
          ).generate();

      final components = spec['components'] as Map;
      expect(components.containsKey('schemas'), isTrue);
      expect(
        (components['schemas'] as Map).containsKey('CreateUserDTO'),
        isTrue,
      );
    });

    test('components.schemas is absent when no schemas provided', () {
      final spec = OpenApiGenerator(routes: [], title: 'API').generate();
      final components = spec['components'] as Map;
      expect(components.containsKey('schemas'), isFalse);
    });

    test('dollar-ref in requestSchema passes through to spec unchanged', () {
      const refKey = r'$ref';
      final route = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/users',
        requestSchema: {refKey: '#/components/schemas/CreateUserDTO'},
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final schema =
          spec['paths']['/users']['post']['requestBody']['content']['application/json']['schema']
              as Map;
      expect(schema[refKey], '#/components/schemas/CreateUserDTO');
    });

    test('dollar-ref in responseSchema passes through to spec unchanged', () {
      const refKey = r'$ref';
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        responseSchema: {refKey: '#/components/schemas/UserResponse'},
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final schema =
          spec['paths']['/users']['get']['responses']['200']['content']['application/json']['schema']
              as Map;
      expect(schema[refKey], '#/components/schemas/UserResponse');
    });

    test('FieldSet.toJsonSchema() can be registered directly as a schema', () {
      final fieldSchema =
          FieldSet({
            'name': Field<String>(validators: [NotEmptyValidator()]),
            'email': Field<String>(validators: [EmailValidator()]),
          }).toJsonSchema();

      final spec =
          OpenApiGenerator(
            routes: [],
            title: 'API',
            schemas: {'CreateUserDTO': fieldSchema},
          ).generate();

      final registered =
          (spec['components']['schemas'] as Map)['CreateUserDTO'] as Map;
      expect(registered['type'], 'object');
      expect((registered['properties'] as Map).containsKey('name'), isTrue);
    });
  });

  // ── EnumValidator ─────────────────────────────────────────────────────────

  group('EnumValidator', () {
    test('validates value in list', () {
      final v = EnumValidator(['draft', 'published', 'archived']);
      expect(v.validate('draft'), isTrue);
      expect(v.validate('published'), isTrue);
    });

    test('rejects value not in list', () {
      final v = EnumValidator(['draft', 'published']);
      expect(v.validate('deleted'), isFalse);
    });

    test('toSchemaProperties returns enum key', () {
      final v = EnumValidator([1, 2, 3]);
      expect(v.toSchemaProperties(), {
        'enum': [1, 2, 3],
      });
    });

    test('default message lists all values', () {
      final v = EnumValidator(['a', 'b']);
      expect(v.validationErrorMessage, contains('a'));
      expect(v.validationErrorMessage, contains('b'));
    });

    test('custom message is used', () {
      final v = EnumValidator(['x'], 'Bad value');
      expect(v.validationErrorMessage, 'Bad value');
    });

    test('works with FieldSet — schema includes enum', () {
      final schema =
          FieldSet({
            'status': Field<String>(
              validators: [
                EnumValidator(['draft', 'published']),
              ],
            ),
          }).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['status'] as Map)['enum'], ['draft', 'published']);
    });

    test('works with FieldSet — validates correctly', () {
      final fields = FieldSet({
        'status': Field<String>(
          validators: [
            EnumValidator(['draft', 'published']),
          ],
        ),
      });
      expect(() => fields.validate({'status': 'draft'}), returnsNormally);
      expect(
        () => fields.validate({'status': 'deleted'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  // ── Field array types ─────────────────────────────────────────────────────

  group('Field array types', () {
    test('List<String> produces jsonType: array', () {
      expect(Field<List<String>>().jsonType, 'array');
    });

    test('List<int> produces arrayItemType: integer', () {
      expect(Field<List<int>>().arrayItemType, 'integer');
    });

    test('List<String> produces arrayItemType: string', () {
      expect(Field<List<String>>().arrayItemType, 'string');
    });

    test('List<double> produces arrayItemType: number', () {
      expect(Field<List<double>>().arrayItemType, 'number');
    });

    test('List<bool> produces arrayItemType: boolean', () {
      expect(Field<List<bool>>().arrayItemType, 'boolean');
    });

    test('non-list field has null arrayItemType', () {
      expect(Field<String>().arrayItemType, isNull);
      expect(Field<int>().arrayItemType, isNull);
    });

    test('FieldSet.toJsonSchema emits items for array field', () {
      final schema =
          FieldSet({
            'tags': Field<List<String>>(),
            'scores': Field<List<int>>(),
          }).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['tags'] as Map)['type'], 'array');
      expect((props['tags'] as Map)['items'], {'type': 'string'});
      expect((props['scores'] as Map)['items'], {'type': 'integer'});
    });

    test('scalar field does not emit items', () {
      final schema = FieldSet({'name': Field<String>()}).toJsonSchema();
      final props = schema['properties'] as Map;
      expect((props['name'] as Map).containsKey('items'), isFalse);
    });
  });
}
