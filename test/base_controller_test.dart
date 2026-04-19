import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Concrete controller used for testing
// ---------------------------------------------------------------------------
class _UserController extends BaseController {
  @override
  List<ApiRoute> get routes => [
        ApiRoute<void, String>(
          method: ApiMethod.get,
          path: '/users',
          typedHandler: (req, _) async => 'all users',
        ),
        ApiRoute<void, String>(
          method: ApiMethod.post,
          path: '/users',
          statusCode: 201,
          typedHandler: (req, _) async => 'created',
        ),
      ];
}

class _EmptyController extends BaseController {
  @override
  List<ApiRoute> get routes => const [];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('BaseController', () {
    test('routes returns the declared ApiRoute list', () {
      final controller = _UserController();
      expect(controller.routes.length, equals(2));
    });

    test('routes contains GET /users', () {
      final controller = _UserController();
      expect(
        controller.routes.any(
          (r) => r.method == ApiMethod.get && r.path == '/users',
        ),
        isTrue,
      );
    });

    test('routes contains POST /users with statusCode 201', () {
      final controller = _UserController();
      final post = controller.routes.firstWhere(
        (r) => r.method == ApiMethod.post,
      );
      expect(post.statusCode, equals(201));
    });

    test('webSocketRoutes defaults to empty list', () {
      final controller = _UserController();
      expect(controller.webSocketRoutes, isEmpty);
    });

    test('empty controller has empty routes and webSocketRoutes', () {
      final controller = _EmptyController();
      expect(controller.routes, isEmpty);
      expect(controller.webSocketRoutes, isEmpty);
    });

    test('routes are callable — GET /users returns 200', () async {
      final controller = _UserController();
      final route = controller.routes.first;
      final response = await route.handler(
        Request('GET', Uri.parse('http://localhost/users')),
      );
      expect(response.statusCode, equals(200));
    });
  });
}
