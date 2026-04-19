import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A WebSocket endpoint that can be registered alongside [ApiRoute]s in a
/// [BaseController].
///
/// ```dart
/// class ChatController extends BaseController {
///   @override
///   List<ApiRoute> get routes => [];
///
///   @override
///   List<WebSocketRoute> get webSocketRoutes => [
///     WebSocketRoute(
///       path: '/ws/chat',
///       handler: (channel, _) async {
///         await for (final message in channel.stream) {
///           channel.sink.add('Echo: $message');
///         }
///       },
///     ),
///   ];
/// }
/// ```
///
/// The [RouterManager] in your generated project calls
/// `controller.webSocketRoutes` and registers each route via `shelf_router`.
class WebSocketRoute {
  /// The URL path for this WebSocket endpoint (e.g. `/ws/chat`).
  final String path;

  /// Called whenever a client opens a connection.
  ///
  /// - [channel] exposes `.stream` (incoming) and `.sink` (outgoing).
  /// - [subprotocol] is the negotiated WebSocket subprotocol, or `null`.
  final void Function(WebSocketChannel channel, String? subprotocol) handler;

  /// Optional middleware applied before the WebSocket upgrade handshake.
  ///
  /// Useful for authentication or rate limiting:
  /// ```dart
  /// WebSocketRoute(
  ///   path: '/ws/chat',
  ///   middlewares: [authMiddleware(jwtService)],
  ///   handler: chatHandler,
  /// )
  /// ```
  final List<Middleware> middlewares;

  /// A short summary for documentation purposes.
  final String? summary;

  const WebSocketRoute({
    required this.path,
    required this.handler,
    this.middlewares = const [],
    this.summary,
  });

  /// Returns a Shelf [Handler] that performs the WebSocket upgrade.
  Handler get shelfHandler => webSocketHandler(handler);
}
