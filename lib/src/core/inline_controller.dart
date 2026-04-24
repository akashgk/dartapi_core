import 'api_route.dart';
import 'base_controller.dart';

/// A [BaseController] that takes its routes as a constructor argument.
///
/// Use this to define routes inline without creating a dedicated controller class:
///
/// ```dart
/// app.addControllers([
///   InlineController([
///     ApiRoute<void, String>(
///       method: ApiMethod.get,
///       path: '/hello',
///       typedHandler: (req, _) async => 'Hello, World!',
///       summary: 'Health check',
///     ),
///   ]),
/// ]);
/// ```
class InlineController extends BaseController {
  @override
  final List<ApiRoute> routes;

  InlineController(this.routes);
}
