import 'api_route.dart';

/// A base class that all controllers must extend in a DartAPI application.
///
/// Each controller is expected to define a list of [ApiRoute]s that describe
/// the endpoints it exposes. The routes will be registered by the server during
/// application startup.
///
/// Controllers group related routes together (e.g., UserController, ProductController),
/// allowing for modular and organized API structure.
abstract class BaseController {
  /// A list of API routes exposed by this controller.
  ///
  /// Each route defines its HTTP method, path, handler, and optional metadata.
  List<ApiRoute> get routes;
}
