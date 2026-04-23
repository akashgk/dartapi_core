import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('WebSocketRoute', () {
    test('stores path, handler, and defaults', () {
      final route = WebSocketRoute(
        path: '/ws/chat',
        handler: (_, _) {},
      );
      expect(route.path, equals('/ws/chat'));
      expect(route.middlewares, isEmpty);
      expect(route.summary, isNull);
    });

    test('stores optional fields', () {
      final route = WebSocketRoute(
        path: '/ws/data',
        handler: (_, _) {},
        summary: 'Data stream',
        middlewares: [
          (Handler inner) => (req) => inner(req),
        ],
      );
      expect(route.summary, equals('Data stream'));
      expect(route.middlewares, hasLength(1));
    });

    test('shelfHandler returns a non-null Handler', () {
      final route = WebSocketRoute(
        path: '/ws/test',
        handler: (channel, _) {
          channel.sink.close();
        },
      );
      expect(route.shelfHandler, isA<Handler>());
    });

    test('handler signature accepts WebSocketChannel and subprotocol', () {
      WebSocketChannel? captured;
      String? capturedProto;
      final route = WebSocketRoute(
        path: '/ws/test',
        handler: (channel, proto) {
          captured = channel;
          capturedProto = proto;
        },
      );
      // Verify the handler can be stored and is callable.
      expect(route.handler, isNotNull);
      // The handler type is correct — assignment proves signature compatibility.
      final void Function(WebSocketChannel, String?) h = route.handler;
      expect(h, isNotNull);
      // Suppress unused variable warnings.
      expect(captured, isNull);
      expect(capturedProto, isNull);
    });
  });

  group('BaseController.webSocketRoutes', () {
    test('defaults to empty list', () {
      final controller = _EmptyController();
      expect(controller.webSocketRoutes, isEmpty);
    });

    test('can be overridden to expose WebSocket routes', () {
      final controller = _WsController();
      expect(controller.webSocketRoutes, hasLength(1));
      expect(controller.webSocketRoutes.first.path, equals('/ws/echo'));
    });
  });
}

class _EmptyController extends BaseController {
  @override
  List<ApiRoute> get routes => [];
}

class _WsController extends BaseController {
  @override
  List<ApiRoute> get routes => [];

  @override
  List<WebSocketRoute> get webSocketRoutes => [
        WebSocketRoute(
          path: '/ws/echo',
          handler: (channel, _) {
            channel.stream.listen((msg) => channel.sink.add(msg));
          },
        ),
      ];
}
