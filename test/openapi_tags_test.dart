import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('ApiRoute.tags', () {
    test('defaults to empty list', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        typedHandler: (req, _) async => 'ok',
      );
      expect(route.tags, isEmpty);
    });

    test('stores provided tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        tags: ['Users', 'Admin'],
        typedHandler: (req, _) async => 'ok',
      );
      expect(route.tags, equals(['Users', 'Admin']));
    });

    test('withTags returns new route with given tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        summary: 'List users',
        typedHandler: (req, _) async => 'ok',
      );
      final tagged = route.withTags(['Users']);
      expect(tagged.tags, equals(['Users']));
      expect(tagged.path, equals('/users'));
      expect(tagged.summary, equals('List users'));
    });

    test('withTags preserves all other fields', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/items',
        summary: 'Create item',
        description: 'Creates one',
        statusCode: 201,
        security: [SecurityScheme.bearer],
        contentType: 'application/json',
        tags: [],
        typedHandler: (req, _) async => 'ok',
      );
      final tagged = route.withTags(['Items']);
      expect(tagged.method, equals(ApiMethod.post));
      expect(tagged.path, equals('/items'));
      expect(tagged.summary, equals('Create item'));
      expect(tagged.description, equals('Creates one'));
      expect(tagged.statusCode, equals(201));
      expect(tagged.security, equals([SecurityScheme.bearer]));
      expect(tagged.contentType, equals('application/json'));
      expect(tagged.tags, equals(['Items']));
    });

    test('original route is unchanged after withTags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/ping',
        tags: [],
        typedHandler: (req, _) async => 'ok',
      );
      route.withTags(['X']);
      expect(route.tags, isEmpty);
    });
  });

  group('BaseController.tag', () {
    test('defaults to null', () {
      final controller = _NoTagController();
      expect(controller.tag, isNull);
    });

    test('override returns custom tag', () {
      final controller = _TaggedController();
      expect(controller.tag, equals('Books'));
    });
  });

  group('RouterManager — controller tag auto-stamping', () {
    test('stamps controller tag onto routes with no tags', () {
      final manager = RouterManager();
      manager.registerController(_TaggedController());
      final routes = manager.collectedRoutes;
      expect(routes.every((r) => r.tags.contains('Books')), isTrue);
    });

    test('does not override explicit route tags', () {
      final manager = RouterManager();
      manager.registerController(_MixedTagController());
      final routes = manager.collectedRoutes;
      final listRoute = routes.firstWhere((r) => r.path == '/mixed/list');
      final detailRoute = routes.firstWhere((r) => r.path == '/mixed/detail');
      // /mixed/list has explicit tags: ['Custom'] — must be preserved
      expect(listRoute.tags, equals(['Custom']));
      // /mixed/detail has no tags — controller tag 'Mixed' is stamped
      expect(detailRoute.tags, equals(['Mixed']));
    });

    test('routes on controller with null tag keep empty tags list', () {
      final manager = RouterManager();
      manager.registerController(_NoTagController());
      final routes = manager.collectedRoutes;
      expect(routes.every((r) => r.tags.isEmpty), isTrue);
    });
  });

  group('OpenApiGenerator — tags in operations', () {
    test('emits tags array on operation when route has tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        tags: ['Users'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final op = spec['paths']['/users']['get'] as Map;
      expect(op['tags'], equals(['Users']));
    });

    test('omits tags key on operation when route has no tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/ping',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final op = spec['paths']['/ping']['get'] as Map;
      expect(op.containsKey('tags'), isFalse);
    });

    test('emits multiple tags on a single operation', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/users',
        tags: ['Users', 'Admin'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final op = spec['paths']['/users']['get'] as Map;
      expect(op['tags'], containsAll(['Users', 'Admin']));
    });
  });

  group('OpenApiGenerator — top-level tags array', () {
    test('emits top-level tags when routes have tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/books',
        tags: ['Books'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final tags = spec['tags'] as List;
      expect(tags.any((t) => t['name'] == 'Books'), isTrue);
    });

    test('omits top-level tags when no routes have tags and no tagDescriptions',
        () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/ping',
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      expect(spec.containsKey('tags'), isFalse);
    });

    test('includes tagDescriptions descriptions in top-level tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/books',
        tags: ['Books'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(
        routes: [route],
        title: 'API',
        tagDescriptions: {'Books': 'Book management endpoints'},
      ).generate();
      final tags = spec['tags'] as List;
      final bookTag = tags.firstWhere((t) => t['name'] == 'Books');
      expect(bookTag['description'], equals('Book management endpoints'));
    });

    test('tag with no description omits description key', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/books',
        tags: ['Books'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec = OpenApiGenerator(routes: [route], title: 'API').generate();
      final tags = spec['tags'] as List;
      final bookTag = tags.firstWhere((t) => t['name'] == 'Books');
      expect((bookTag as Map).containsKey('description'), isFalse);
    });

    test('tagDescriptions-only tag appears in top-level tags even with no routes',
        () {
      final spec = OpenApiGenerator(
        routes: [],
        title: 'API',
        tagDescriptions: {'Misc': 'Miscellaneous'},
      ).generate();
      final tags = spec['tags'] as List;
      expect(tags.any((t) => t['name'] == 'Misc'), isTrue);
    });

    test('deduplicates tags across multiple routes', () {
      final r1 = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/a',
        tags: ['Users'],
        typedHandler: (req, _) async => 'ok',
      );
      final r2 = ApiRoute<void, String>(
        method: ApiMethod.post,
        path: '/b',
        tags: ['Users'],
        typedHandler: (req, _) async => 'ok',
      );
      final spec =
          OpenApiGenerator(routes: [r1, r2], title: 'API').generate();
      final tags = spec['tags'] as List;
      final userTags = tags.where((t) => t['name'] == 'Users').toList();
      expect(userTags.length, equals(1));
    });

    test('toJson output includes tags', () {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/books',
        tags: ['Books'],
        typedHandler: (req, _) async => 'ok',
      );
      final json = OpenApiGenerator(routes: [route], title: 'API').toJson();
      final decoded = jsonDecode(json);
      expect(decoded['tags'], isNotNull);
    });
  });

  group('DocsController — tagDescriptions', () {
    test('forwards tagDescriptions to OpenApiGenerator', () async {
      final route = ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/books',
        tags: ['Books'],
        typedHandler: (req, _) async => 'ok',
      );
      final controller = DocsController(
        apiRoutes: [route],
        title: 'API',
        tagDescriptions: {'Books': 'All about books'},
      );
      final jsonRoute = controller.routes.firstWhere(
        (r) => r.path == '/openapi.json',
      );
      final result = await jsonRoute.typedHandler(_dummyRequest(), null);
      final decoded = jsonDecode(result);
      final tags = decoded['tags'] as List;
      final bookTag = tags.firstWhere((t) => t['name'] == 'Books');
      expect(bookTag['description'], equals('All about books'));
    });
  });
}

// ── Test controllers ──────────────────────────────────────────────────────────

class _NoTagController extends BaseController {
  @override
  List<ApiRoute> get routes => [
    ApiRoute<void, String>(
      method: ApiMethod.get,
      path: '/notag',
      typedHandler: (req, _) async => 'ok',
    ),
  ];
}

class _TaggedController extends BaseController {
  @override
  String? get tag => 'Books';

  @override
  List<ApiRoute> get routes => [
    ApiRoute<void, String>(
      method: ApiMethod.get,
      path: '/books',
      typedHandler: (req, _) async => 'ok',
    ),
    ApiRoute<void, String>(
      method: ApiMethod.post,
      path: '/books',
      typedHandler: (req, _) async => 'ok',
    ),
  ];
}

class _MixedTagController extends BaseController {
  @override
  String? get tag => 'Mixed';

  @override
  List<ApiRoute> get routes => [
    // Explicit tags — must be preserved
    ApiRoute<void, String>(
      method: ApiMethod.get,
      path: '/mixed/list',
      tags: ['Custom'],
      typedHandler: (req, _) async => 'ok',
    ),
    // No tags — controller tag should be stamped
    ApiRoute<void, String>(
      method: ApiMethod.get,
      path: '/mixed/detail',
      typedHandler: (req, _) async => 'ok',
    ),
  ];
}

Request _dummyRequest() => Request('GET', Uri.parse('http://localhost/test'));
