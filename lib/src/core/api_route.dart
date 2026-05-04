import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'api_exception.dart';
import 'api_methods.dart';
import 'serializable.dart';
import '../middleware/cache_middleware.dart';
import '../openapi/security_scheme.dart';
import '../openapi/query_param_spec.dart';

/// Represents a single HTTP route in your DartAPI application.
///
/// Each route defines the HTTP method, path, handler function, optional DTO parser,
/// middleware, and optional metadata for documentation or validation purposes.
///
/// This class wraps the route into a Shelf-compatible [Handler].
class ApiRoute<ApiInput, ApiOutput> {
  /// The HTTP method for this route (GET, POST, PUT, DELETE, etc.)
  final ApiMethod method;

  /// The URL path of the route (e.g., `/users`, `/products/:id`)
  final String path;

  /// The typed handler function that processes the request and returns a typed response.
  ///
  /// The [ApiInput] is the decoded request body (if any).
  /// The handler must return a [Future<ApiOutput>], which is serialized to JSON.
  final Future<ApiOutput> Function(Request, ApiInput?) typedHandler;

  /// Optional function to parse the request body into an instance of [ApiInput].
  ///
  /// This allows custom decoding or validation logic before the handler is called.
  final ApiInput? Function(Map<String, dynamic>)? dtoParser;

  /// Middleware specific to this route.
  ///
  /// Middleware can include authentication, logging, rate limiting, etc.
  final List<Middleware> middlewares;

  /// A short summary describing what this route does.
  ///
  /// Used for generating documentation or OpenAPI metadata.
  final String? summary;

  /// A more detailed explanation of the route's behavior or purpose.
  final String? description;

  /// Optional schema definition of the request body, for documentation or validation.
  final Map<String, dynamic>? requestSchema;

  /// Optional schema definition of the response body, for documentation or validation.
  final Map<String, dynamic>? responseSchema;

  /// The HTTP status code returned on a successful response. Defaults to 200.
  ///
  /// Use this to return 201 for resource creation, 204 for deletion, etc.
  ///
  /// ```dart
  /// ApiRoute(
  ///   method: ApiMethod.post,
  ///   path: '/users',
  ///   statusCode: 201,
  ///   typedHandler: createUser,
  /// )
  /// ```
  final int statusCode;

  /// Security schemes required to access this route.
  ///
  /// Used when generating OpenAPI documentation to display the lock icon
  /// in Swagger UI and ReDoc.
  ///
  /// ```dart
  /// ApiRoute(
  ///   security: [SecurityScheme.bearer],
  ///   ...
  /// )
  /// ```
  final List<SecurityScheme> security;

  /// The Content-Type header returned with the response.
  ///
  /// Defaults to `'application/json'`. Set to `'text/html'` for HTML responses.
  final String contentType;

  /// Optional TTL for per-route response caching.
  ///
  /// When set, responses from this route are cached in memory for the given
  /// duration. Only GET requests that return 200 are cached.
  ///
  /// ```dart
  /// ApiRoute(
  ///   method: ApiMethod.get,
  ///   path: '/products',
  ///   cacheTtl: Duration(minutes: 10),
  ///   typedHandler: (req, _) async => fetchProducts(),
  /// )
  /// ```
  final Duration? cacheTtl;

  /// Query parameters to document in the OpenAPI spec.
  ///
  /// These appear under `parameters` with `in: query` in the generated spec.
  ///
  /// ```dart
  /// ApiRoute(
  ///   method: ApiMethod.get,
  ///   path: '/users',
  ///   queryParams: [
  ///     QueryParamSpec('page', type: 'integer', defaultValue: 1),
  ///     QueryParamSpec('limit', type: 'integer', defaultValue: 20),
  ///     QueryParamSpec('search', description: 'Filter by name'),
  ///   ],
  ///   typedHandler: listUsers,
  /// )
  /// ```
  final List<QueryParamSpec> queryParams;

  /// OpenAPI tags for grouping this route in Swagger UI / ReDoc.
  ///
  /// Routes with the same tag are displayed together under a collapsible
  /// section in Swagger UI. If empty, the route appears in the default group.
  ///
  /// Tags can also be set automatically by overriding [BaseController.tag]
  /// on the controller that owns this route.
  ///
  /// ```dart
  /// ApiRoute(
  ///   method: ApiMethod.get,
  ///   path: '/users',
  ///   tags: ['Users'],
  ///   typedHandler: listUsers,
  /// )
  /// ```
  final List<String> tags;

  /// Marks this route as deprecated.
  ///
  /// When `true`:
  /// - The `deprecated: true` flag appears in the OpenAPI spec, displaying
  ///   a strikethrough in Swagger UI and ReDoc.
  /// - Responses carry a `Deprecation: true` header (RFC 8594) so clients
  ///   that observe HTTP headers can detect the deprecation at runtime.
  ///
  /// ```dart
  /// ApiRoute(
  ///   method: ApiMethod.get,
  ///   path: '/v1/users',
  ///   deprecated: true,
  ///   summary: 'List users (deprecated — use /v2/users)',
  ///   typedHandler: listUsersV1,
  /// )
  /// ```
  final bool deprecated;

  /// Creates a new [ApiRoute] instance.
  ///
  /// You must provide the [method], [path], and [typedHandler].
  /// All other fields are optional.
  const ApiRoute({
    required this.method,
    required this.path,
    required this.typedHandler,
    this.dtoParser,
    this.middlewares = const [],
    this.cacheTtl,
    this.summary,
    this.description,
    this.requestSchema,
    this.responseSchema,
    this.statusCode = 200,
    this.security = const [],
    this.contentType = 'application/json',
    this.queryParams = const [],
    this.tags = const [],
    this.deprecated = false,
  });

  /// Returns a copy of this route with the given [newTags], leaving all other
  /// fields unchanged. Used by [RouterManager] to apply a controller's default
  /// tag to routes that declare no explicit tags.
  ApiRoute<ApiInput, ApiOutput> withTags(List<String> newTags) =>
      ApiRoute<ApiInput, ApiOutput>(
        method: method,
        path: path,
        typedHandler: typedHandler,
        dtoParser: dtoParser,
        middlewares: middlewares,
        cacheTtl: cacheTtl,
        summary: summary,
        description: description,
        requestSchema: requestSchema,
        responseSchema: responseSchema,
        statusCode: statusCode,
        security: security,
        contentType: contentType,
        queryParams: queryParams,
        tags: newTags,
        deprecated: deprecated,
      );

  /// Effective middlewares for this route, including [cacheMiddleware] when
  /// [cacheTtl] is set. Used by [RouterManager] when registering routes.
  ///
  /// Cache is placed last so it becomes the outermost wrapper — a cache HIT
  /// short-circuits before any other per-route middleware runs.
  List<Middleware> get effectiveMiddlewares => [
    ...middlewares,
    if (cacheTtl != null) cacheMiddleware(ttl: cacheTtl!),
  ];

  /// Returns a Shelf-compatible [Handler] for this route.
  ///
  /// It wraps request body parsing, error handling, and response serialization.
  Handler get handler => (Request request) async {
    try {
      ApiInput? dto;

      if (dtoParser != null) {
        final body = await request.readAsString();
        dto = dtoParser?.call(jsonDecode(body));
      }

      final result = await typedHandler(request, dto);

      if (result == null) {
        return Response(204);
      }

      // Allow handlers to return a pre-built Response (e.g., SSE, file downloads).
      if (result is Response) return result;

      return Response(
        statusCode,
        body: _serialize(result),
        headers: {
          'Content-Type': contentType,
          if (deprecated) 'Deprecation': 'true',
        },
      );
    } on ValidationException catch (e) {
      return Response(
        422,
        body: jsonEncode({'errors': e.errors}),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (e) {
      return Response(
        400,
        body: _serialize({'error': 'Bad Request', 'message': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } on ApiException catch (e) {
      return Response(
        e.statusCode,
        body: _serialize({'error': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: _serialize({
          'error': 'Internal Server Error',
          'message': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  };
}

/// Converts the result of the handler into a JSON-encoded response body.
///
/// Supports strings, maps, lists, and classes implementing [Serializable].
String _serialize(dynamic data) {
  if (data is String) return data;
  if (data is bool || data is num) return jsonEncode(data);
  if (data is Map || data is List) return jsonEncode(data);
  if (data is Serializable) return jsonEncode(data.toJson());

  throw Exception("Unable to serialize response of type ${data.runtimeType}");
}
