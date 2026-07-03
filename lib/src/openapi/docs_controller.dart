import '../core/api_methods.dart';
import '../core/api_route.dart';
import '../core/base_controller.dart';
import 'openapi_generator.dart';

/// Pinned UI asset versions — bumped deliberately with releases, never
/// `@latest`, so `/docs` cannot break because a CDN shipped a new major.
const String kSwaggerUiVersion = '5.32.8';
const String kRedocVersion = '2.5.3';

const String _defaultSwaggerCss =
    'https://cdn.jsdelivr.net/npm/swagger-ui-dist@$kSwaggerUiVersion/swagger-ui.css';
const String _defaultSwaggerJs =
    'https://cdn.jsdelivr.net/npm/swagger-ui-dist@$kSwaggerUiVersion/swagger-ui-bundle.js';
const String _defaultRedocJs =
    'https://cdn.jsdelivr.net/npm/redoc@$kRedocVersion/bundles/redoc.standalone.js';

/// A [BaseController] that serves OpenAPI documentation endpoints.
///
/// Registers three routes:
/// - `GET /openapi.json` — OpenAPI 3.0 spec (generated once, then cached)
/// - `GET /docs`         — Swagger UI
/// - `GET /redoc`        — ReDoc
///
/// Routes are read lazily through [routesProvider] on the first request, so
/// the registration order of controllers no longer matters. The three docs
/// routes themselves are excluded from the spec.
///
/// UI assets are loaded from jsdelivr at **pinned versions**
/// ([kSwaggerUiVersion], [kRedocVersion]). For air-gapped or CSP-restricted
/// deployments, serve the files yourself (e.g. `app.serveStatic('/assets',
/// 'third_party')`) and point [swaggerUiCssUrl] / [swaggerUiJsUrl] /
/// [redocJsUrl] at them.
///
/// Typically used via [DartAPI.enableDocs()]:
/// ```dart
/// app.addControllers([userController, productController]);
/// app.enableDocs(title: 'My App', version: '1.0.0');
/// await app.start();
/// ```
class DocsController extends BaseController {
  /// Returns the routes to document, read lazily on first request.
  final List<ApiRoute> Function() routesProvider;

  final String title;
  final String version;
  final String description;
  final List<String> servers;
  final String apiKeyHeader;
  final Map<String, Map<String, dynamic>> schemas;
  final Map<String, String> tagDescriptions;
  final String swaggerUiCssUrl;
  final String swaggerUiJsUrl;
  final String redocJsUrl;

  String? _cachedSpecJson;

  DocsController({
    required this.routesProvider,
    required this.title,
    this.version = '1.0.0',
    this.description = '',
    this.servers = const [],
    this.apiKeyHeader = 'X-API-Key',
    this.schemas = const {},
    this.tagDescriptions = const {},
    String? swaggerUiCssUrl,
    String? swaggerUiJsUrl,
    String? redocJsUrl,
  }) : swaggerUiCssUrl = swaggerUiCssUrl ?? _defaultSwaggerCss,
       swaggerUiJsUrl = swaggerUiJsUrl ?? _defaultSwaggerJs,
       redocJsUrl = redocJsUrl ?? _defaultRedocJs;

  static const _ownPaths = {'/openapi.json', '/docs', '/redoc'};

  String get _specJson =>
      _cachedSpecJson ??=
          OpenApiGenerator(
            routes:
                routesProvider()
                    .where((r) => !_ownPaths.contains(r.path))
                    .toList(),
            title: title,
            version: version,
            description: description,
            servers: servers,
            apiKeyHeader: apiKeyHeader,
            schemas: schemas,
            tagDescriptions: tagDescriptions,
          ).toJson();

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
    typedHandler: (req, _) async => _specJson,
  );

  ApiRoute<void, String> _swaggerUiRoute() => ApiRoute<void, String>(
    method: ApiMethod.get,
    path: '/docs',
    summary: 'Swagger UI',
    contentType: 'text/html',
    typedHandler:
        (req, _) async => _swaggerHtml(title, swaggerUiCssUrl, swaggerUiJsUrl),
  );

  ApiRoute<void, String> _redocRoute() => ApiRoute<void, String>(
    method: ApiMethod.get,
    path: '/redoc',
    summary: 'ReDoc UI',
    contentType: 'text/html',
    typedHandler: (req, _) async => _redocHtml(title, redocJsUrl),
  );
}

String _swaggerHtml(String title, String cssUrl, String jsUrl) =>
    '''<!DOCTYPE html>
<html>
  <head>
    <title>$title — Swagger UI</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="$cssUrl">
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="$jsUrl"></script>
    <script>
      SwaggerUIBundle({
        url: '/openapi.json',
        dom_id: '#swagger-ui',
        presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
        layout: 'BaseLayout',
        deepLinking: true,
        filter: true,
        tryItOutEnabled: true,
        persistAuthorization: true,
      });
    </script>
  </body>
</html>''';

String _redocHtml(String title, String jsUrl) => '''<!DOCTYPE html>
<html>
  <head>
    <title>$title — ReDoc</title>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1">
  </head>
  <body>
    <redoc spec-url="/openapi.json"></redoc>
    <script src="$jsUrl"></script>
  </body>
</html>''';
