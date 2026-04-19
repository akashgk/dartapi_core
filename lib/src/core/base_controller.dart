import 'api_route.dart';
import 'websocket_route.dart';

/// Base class for all DartAPI controllers.
///
/// Implement [routes] to expose HTTP endpoints and, optionally,
/// [webSocketRoutes] to expose WebSocket endpoints.
abstract class BaseController {
  /// HTTP routes exposed by this controller.
  List<ApiRoute> get routes;

  /// WebSocket routes exposed by this controller.
  ///
  /// Defaults to an empty list — override only when needed.
  List<WebSocketRoute> get webSocketRoutes => const [];
}
