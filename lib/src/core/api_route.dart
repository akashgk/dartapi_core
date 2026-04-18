import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'api_exception.dart';
import 'api_methods.dart';
import 'serializable.dart';
import '../openapi/security_scheme.dart';

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
    this.summary,
    this.description,
    this.requestSchema,
    this.responseSchema,
    this.statusCode = 200,
    this.security = const [],
    this.contentType = 'application/json',
  });

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

      return Response(
        statusCode,
        body: _serialize(result),
        headers: {'Content-Type': contentType},
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
  if (data is Map || data is List) return jsonEncode(data);
  if (data is Serializable) return jsonEncode(data.toJson());

  throw Exception("Unable to serialize response of type ${data.runtimeType}");
}
