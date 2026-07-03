import 'dart:convert';

import '../core/api_route.dart';
import 'security_scheme.dart';

/// Generates an OpenAPI 3.0 specification from a list of [ApiRoute]s.
///
/// ```dart
/// final generator = OpenApiGenerator(
///   routes: allRoutes,
///   title: 'My App',
///   version: '1.0.0',
///   servers: ['https://api.example.com'],
///   schemas: {
///     'CreateUserDTO': CreateUserDTO.fields.toJsonSchema(),
///     'UserResponse':  UserResponse.schema,
///   },
/// );
/// final json = generator.toJson();    // pretty-printed JSON string
/// final map  = generator.generate();  // raw Map<String, dynamic>
/// ```
///
/// Named schemas registered in [schemas] appear under
/// `components/schemas` and can be referenced in route schemas with
/// `{'\$ref': '#/components/schemas/CreateUserDTO'}`.
///
/// Beyond what each route declares, the generator documents what the
/// framework actually does at runtime:
///
/// - routes with a body parser get `422 Validation Error` and
///   `400 Bad Request` responses (thrown by `ApiRoute.handler`);
/// - routes with `security` get a `401 Unauthorized` response
///   (returned by `authMiddleware` / `apiKeyMiddleware`);
/// - every operation gets an `operationId` (derived from method + path
///   unless the route sets one), so OpenAPI client generators produce
///   usable method names.
class OpenApiGenerator {
  final List<ApiRoute> routes;
  final String title;
  final String version;
  final String description;

  /// Server URLs listed in the spec's `servers` array. Drives the base URL
  /// of Swagger UI's "Try it out" and of generated clients.
  final List<String> servers;

  /// Header name documented for [SecurityScheme.apiKey] routes.
  /// Must match the `headerName` passed to `apiKeyMiddleware`.
  final String apiKeyHeader;

  /// Named schemas to register under `components/schemas`.
  ///
  /// Routes can reference these with `{'\$ref': '#/components/schemas/Name'}`.
  final Map<String, Map<String, dynamic>> schemas;

  /// Optional descriptions for OpenAPI tag objects in the top-level `tags` array.
  ///
  /// Keys are tag names; values are the human-readable descriptions that appear
  /// in Swagger UI and ReDoc below each group heading.
  final Map<String, String> tagDescriptions;

  const OpenApiGenerator({
    required this.routes,
    required this.title,
    this.version = '1.0.0',
    this.description = '',
    this.servers = const [],
    this.apiKeyHeader = 'X-API-Key',
    this.schemas = const {},
    this.tagDescriptions = const {},
  });

  /// Returns the OpenAPI 3.0 specification as a [Map].
  Map<String, dynamic> generate() {
    final paths = <String, dynamic>{};
    var needsValidationError = false;
    var needsError = false;

    for (final route in routes) {
      final openApiPath = toOpenApiPath(route.path);
      final method = route.method.value.toLowerCase();

      paths[openApiPath] ??= <String, dynamic>{};

      final operation = <String, dynamic>{
        'operationId': route.operationId ?? _defaultOperationId(route),
      };
      if (route.tags.isNotEmpty) operation['tags'] = route.tags;
      if (route.summary != null) operation['summary'] = route.summary;
      if (route.description != null) {
        operation['description'] = route.description;
      }
      if (route.deprecated) operation['deprecated'] = true;

      // Parameters: path params first, then query params.
      final parameters = <Map<String, dynamic>>[];

      final declared = {for (final p in route.pathParams) p.name: p};
      for (final name in _extractPathParams(route.path)) {
        final spec = declared[name];
        parameters.add(
          spec?.toOpenApiParameter() ??
              {
                'name': name,
                'in': 'path',
                'required': true,
                'schema': {'type': 'string'},
              },
        );
      }

      for (final qp in route.queryParams) {
        parameters.add(qp.toOpenApiParameter());
      }

      if (parameters.isNotEmpty) operation['parameters'] = parameters;

      // Request body — explicit schema, or derived from the route's FieldSet.
      final requestSchema = route.effectiveRequestSchema;
      if (requestSchema != null) {
        operation['requestBody'] = {
          'required': true,
          'content': {
            'application/json': {'schema': requestSchema},
          },
        };
      }

      // Security.
      if (route.security.isNotEmpty) {
        operation['security'] =
            route.security
                .map(
                  (s) => switch (s) {
                    SecurityScheme.bearer => {'bearerAuth': <String>[]},
                    SecurityScheme.apiKey => {'apiKeyAuth': <String>[]},
                  },
                )
                .toList();
      }

      // Responses: success + automatic error responses + explicit overrides.
      final responses = <String, dynamic>{};

      final successEntry = <String, dynamic>{
        'description': _statusDescription(route.statusCode),
      };
      if (route.responseSchema != null) {
        successEntry['content'] = {
          'application/json': {'schema': route.responseSchema},
        };
      }
      responses[route.statusCode.toString()] = successEntry;

      // ApiRoute.handler maps ValidationException → 422 and malformed
      // JSON (FormatException) → 400 for any route that parses a body.
      if (route.dtoParser != null || route.requestFields != null) {
        needsValidationError = true;
        needsError = true;
        responses['422'] = {
          'description': 'Validation Error',
          'content': {
            'application/json': {
              'schema': {r'$ref': '#/components/schemas/ValidationError'},
            },
          },
        };
        responses['400'] = {
          'description': 'Bad Request — malformed JSON body',
          'content': {
            'application/json': {
              'schema': {r'$ref': '#/components/schemas/Error'},
            },
          },
        };
      }

      // authMiddleware / apiKeyMiddleware reject with 401.
      if (route.security.isNotEmpty) {
        needsError = true;
        responses['401'] = {
          'description': 'Unauthorized — missing or invalid credentials',
          'content': {
            'application/json': {
              'schema': {r'$ref': '#/components/schemas/Error'},
            },
          },
        };
      }

      // Explicit route responses always win.
      for (final entry in route.responses.entries) {
        responses[entry.key.toString()] = entry.value.toOpenApiResponse();
      }

      operation['responses'] = responses;

      (paths[openApiPath] as Map<String, dynamic>)[method] = operation;
    }

    final componentSchemas = <String, Map<String, dynamic>>{
      ...schemas,
      if (needsValidationError && !schemas.containsKey('ValidationError'))
        'ValidationError': _validationErrorSchema,
      if (needsError && !schemas.containsKey('Error')) 'Error': _errorSchema,
    };

    final components = <String, dynamic>{
      'securitySchemes': {
        'bearerAuth': {
          'type': 'http',
          'scheme': 'bearer',
          'bearerFormat': 'JWT',
        },
        'apiKeyAuth': {'type': 'apiKey', 'in': 'header', 'name': apiKeyHeader},
      },
      if (componentSchemas.isNotEmpty) 'schemas': componentSchemas,
    };

    // Collect all unique tag names (preserving first-seen order).
    final seenTags = <String>{};
    for (final route in routes) {
      seenTags.addAll(route.tags);
    }
    seenTags.addAll(tagDescriptions.keys);

    final topLevelTags =
        seenTags.map((name) {
          final entry = <String, dynamic>{'name': name};
          final desc = tagDescriptions[name];
          if (desc != null) entry['description'] = desc;
          return entry;
        }).toList();

    return {
      'openapi': '3.0.3',
      'info': {
        'title': title,
        'version': version,
        if (description.isNotEmpty) 'description': description,
      },
      if (servers.isNotEmpty)
        'servers': [
          for (final url in servers) {'url': url},
        ],
      if (topLevelTags.isNotEmpty) 'tags': topLevelTags,
      'paths': paths,
      'components': components,
    };
  }

  /// Returns the spec as a pretty-printed JSON string.
  String toJson() => const JsonEncoder.withIndent('  ').convert(generate());
}

/// Matches the 422 body produced by `ApiRoute.handler` for
/// `ValidationException`: `{"errors": [{"field": ..., "message": ...}]}`.
const Map<String, dynamic> _validationErrorSchema = {
  'type': 'object',
  'properties': {
    'errors': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'field': {'type': 'string'},
          'message': {'type': 'string'},
        },
      },
    },
  },
};

/// Matches the error envelope produced by the framework:
/// `{"error": "...", "message": "..."}` (message present on 400s).
const Map<String, dynamic> _errorSchema = {
  'type': 'object',
  'properties': {
    'error': {'type': 'string'},
    'message': {'type': 'string'},
  },
  'required': ['error'],
};

/// Converts a shelf_router path (e.g. `/users/<id>`) to OpenAPI format (`/users/{id}`).
String toOpenApiPath(String path) =>
    path.replaceAllMapped(RegExp(r'<(\w+)>'), (m) => '{${m[1]}}');

List<String> _extractPathParams(String path) =>
    RegExp(r'<(\w+)>').allMatches(path).map((m) => m[1]!).toList();

/// `GET /api/v1/users/<id>` → `get_api_v1_users_by_id`.
String _defaultOperationId(ApiRoute route) {
  final segments = route.path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(
        (s) =>
            s.startsWith('<')
                ? 'by_${s.substring(1, s.length - 1)}'
                : s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_'),
      );
  final slug = segments.isEmpty ? 'root' : segments.join('_');
  return '${route.method.value.toLowerCase()}_$slug'.toLowerCase();
}

String _statusDescription(int code) => switch (code) {
  200 => 'Success',
  201 => 'Created',
  204 => 'No Content',
  400 => 'Bad Request',
  401 => 'Unauthorized',
  403 => 'Forbidden',
  404 => 'Not Found',
  422 => 'Unprocessable Entity',
  500 => 'Internal Server Error',
  _ => 'Response',
};
