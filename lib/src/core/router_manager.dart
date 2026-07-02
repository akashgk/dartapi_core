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

  /// Registers every HTTP and WebSocket route of [controller].
  ///
  /// When [prefix] is non-empty (e.g. `/api/v1`) it is prepended to every
  /// route path, both for routing and in the OpenAPI spec.
  void registerController(BaseController controller, {String prefix = ''}) {
    final controllerTag = controller.tag;

    for (final ApiRoute route in controller.routes) {
      var effectiveRoute = route;
      // Stamp controller tag onto routes that declare no explicit tags.
      if (controllerTag != null && route.tags.isEmpty) {
        effectiveRoute = effectiveRoute.withTags([controllerTag]);
      }
      final fullPath = _prefixPath(prefix, route.path);
      if (fullPath != route.path) {
        effectiveRoute = effectiveRoute.withPath(fullPath);
      }
      _collectedRoutes.add(effectiveRoute);
      Handler finalHandler = effectiveRoute.handler;

      for (final Middleware routeMiddleWare
          in effectiveRoute.effectiveMiddlewares) {
        finalHandler = routeMiddleWare(finalHandler);
      }

      _router.add(effectiveRoute.method.value, fullPath, finalHandler);
    }

    for (final WebSocketRoute wsRoute in controller.webSocketRoutes) {
      Handler finalHandler = wsRoute.shelfHandler;

      for (final Middleware mw in wsRoute.middlewares) {
        finalHandler = mw(finalHandler);
      }

      _router.get(_prefixPath(prefix, wsRoute.path), finalHandler);
    }
  }

  /// Mounts a raw Shelf [handler] under [prefix] (used by
  /// `DartAPI.serveStatic`).
  void mount(String prefix, Handler handler) => _router.mount(prefix, handler);

  static String _prefixPath(String prefix, String path) {
    if (prefix.isEmpty) return path;
    var p = prefix.startsWith('/') ? prefix : '/$prefix';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p == '/') return path;
    final suffix = path.startsWith('/') ? path : '/$path';
    return suffix == '/' ? p : '$p$suffix';
  }
}
