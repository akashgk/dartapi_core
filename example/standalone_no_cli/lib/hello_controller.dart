import 'package:dartapi_core/dartapi_core.dart';

// A controller groups related routes under a single class.
// Extend BaseController and implement `get routes`.
class HelloController extends BaseController {
  @override
  List<ApiRoute> get routes => [
        ApiRoute(
          method: ApiMethod.get,
          path: '/hello',
          summary: 'Say hello',
          description: 'Returns a simple greeting.',
          typedHandler: (req, _) async => {
            'message': 'Hello from my_api!',
            'version': '1.0.0',
          },
        ),

        // Path parameters use <name> syntax (shelf_router style).
        ApiRoute<void, Map<String, dynamic>>(
          method: ApiMethod.get,
          path: '/hello/<name>',
          summary: 'Greet by name',
          typedHandler: (req, _) async => {
            // req.pathParam<T>() extracts and casts the path segment.
            'message': 'Hello, ${req.pathParam<String>('name')}!',
          },
        ),
      ];
}
