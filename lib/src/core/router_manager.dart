import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'api_route.dart';
import 'base_controller.dart';
import 'websocket_route.dart';

/// Registers [BaseController] instances with a Shelf [Router] and collects
/// all [ApiRoute]s for OpenAPI generation.
class RouterManager {
  final Router _router = Router();
  final List<ApiRoute> _collectedRoutes = [];

  Router get handler => _router;

  /// All routes registered so far (read-only snapshot).
  List<ApiRoute> get collectedRoutes => List.unmodifiable(_collectedRoutes);

  void registerController(BaseController controller) {
    final controllerTag = controller.tag;

    for (final ApiRoute route in controller.routes) {
      // Stamp controller tag onto routes that declare no explicit tags.
      final effectiveRoute =
          (controllerTag != null && route.tags.isEmpty)
              ? route.withTags([controllerTag])
              : route;
      _collectedRoutes.add(effectiveRoute);
      Handler finalHandler = route.handler;

      for (final Middleware routeMiddleWare in route.effectiveMiddlewares) {
        finalHandler = routeMiddleWare(finalHandler);
      }

      _router.add(route.method.value, route.path, finalHandler);
    }

    for (final WebSocketRoute wsRoute in controller.webSocketRoutes) {
      Handler finalHandler = wsRoute.shelfHandler;

      for (final Middleware mw in wsRoute.middlewares) {
        finalHandler = mw(finalHandler);
      }

      _router.get(wsRoute.path, finalHandler);
    }
  }
}
