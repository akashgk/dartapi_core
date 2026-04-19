import '../core/api_methods.dart';
import '../core/api_route.dart';
import '../core/base_controller.dart';
import 'openapi_generator.dart';

/// A [BaseController] that serves OpenAPI documentation endpoints.
///
/// Registers three routes:
/// - `GET /openapi.json` — raw OpenAPI 3.0 spec
/// - `GET /docs`         — Swagger UI (CDN-hosted)
/// - `GET /redoc`        — ReDoc UI (CDN-hosted)
///
/// Typically used via [DartAPI.enableDocs()]:
/// ```dart
/// app.addControllers([userController, productController]);
/// app.enableDocs(title: 'My App', version: '1.0.0');
/// await app.start();
/// ```
class DocsController extends BaseController {
  final List<ApiRoute> apiRoutes;
  final String title;
  final String version;
  final String description;

  DocsController({
    required this.apiRoutes,
    required this.title,
    this.version = '1.0.0',
    this.description = '',
  });

  @override
  List<ApiRoute> get routes => [
        _openApiJsonRoute(),
        _swaggerUiRoute(),
        _redocRoute(),
      ];

  ApiRoute<void, String> _openApiJsonRoute() => ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/openapi.json',
        summary: 'OpenAPI 3.0 specification',
        typedHandler: (req, _) async => OpenApiGenerator(
          routes: apiRoutes,
          title: title,
          version: version,
          description: description,
        ).toJson(),
      );

  ApiRoute<void, String> _swaggerUiRoute() => ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/docs',
        summary: 'Swagger UI',
        contentType: 'text/html',
        typedHandler: (req, _) async => _swaggerHtml(title),
      );

  ApiRoute<void, String> _redocRoute() => ApiRoute<void, String>(
        method: ApiMethod.get,
        path: '/redoc',
        summary: 'ReDoc UI',
        contentType: 'text/html',
        typedHandler: (req, _) async => _redocHtml(title),
      );
}

String _swaggerHtml(String title) => '''<!DOCTYPE html>
<html>
  <head>
    <title>$title — Swagger UI</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css">
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
    <script>
      SwaggerUIBundle({
        url: '/openapi.json',
        dom_id: '#swagger-ui',
        presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
        layout: 'BaseLayout',
        persistAuthorization: true,
      });
    </script>
  </body>
</html>''';

String _redocHtml(String title) => '''<!DOCTYPE html>
<html>
  <head>
    <title>$title — ReDoc</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
  </head>
  <body>
    <redoc spec-url="/openapi.json"></redoc>
    <script src="https://cdn.jsdelivr.net/npm/redoc/bundles/redoc.standalone.js"></script>
  </body>
</html>''';
