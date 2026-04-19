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
/// );
/// final json = generator.toJson();     // pretty-printed JSON string
/// final map  = generator.generate();   // raw Map<String, dynamic>
/// ```
class OpenApiGenerator {
  final List<ApiRoute> routes;
  final String title;
  final String version;
  final String description;

  const OpenApiGenerator({
    required this.routes,
    required this.title,
    this.version = '1.0.0',
    this.description = '',
  });

  /// Returns the OpenAPI 3.0 specification as a [Map].
  Map<String, dynamic> generate() {
    final paths = <String, dynamic>{};
    for (final route in routes) {
      final openApiPath = _toOpenApiPath(route.path);
      final method = route.method.value.toLowerCase();

      paths[openApiPath] ??= <String, dynamic>{};

      final operation = <String, dynamic>{};
      if (route.summary != null) operation['summary'] = route.summary;
      if (route.description != null) {
        operation['description'] = route.description;
      }

      // Path parameters inferred from the path pattern.
      final pathParams = _extractPathParams(route.path);
      if (pathParams.isNotEmpty) {
        operation['parameters'] = pathParams
            .map(
              (p) => {
                'name': p,
                'in': 'path',
                'required': true,
                'schema': {'type': 'string'},
              },
            )
            .toList();
      }

      // Request body.
      if (route.requestSchema != null) {
        operation['requestBody'] = {
          'required': true,
          'content': {
            'application/json': {'schema': route.requestSchema},
          },
        };
      }

      // Security.
      if (route.security.isNotEmpty) {
        operation['security'] = route.security.map((s) {
          if (s == SecurityScheme.bearer) {
            return {'bearerAuth': <String>[]};
          }
          return <String, dynamic>{};
        }).toList();
      }

      // Response.
      final statusStr = route.statusCode.toString();
      final responseEntry = <String, dynamic>{
        'description': _statusDescription(route.statusCode),
      };
      if (route.responseSchema != null) {
        responseEntry['content'] = {
          'application/json': {'schema': route.responseSchema},
        };
      }
      operation['responses'] = {statusStr: responseEntry};

      (paths[openApiPath] as Map<String, dynamic>)[method] = operation;
    }

    final spec = <String, dynamic>{
      'openapi': '3.0.0',
      'info': {
        'title': title,
        'version': version,
        if (description.isNotEmpty) 'description': description,
      },
      'paths': paths,
      'components': {
        'securitySchemes': {
          'bearerAuth': {
            'type': 'http',
            'scheme': 'bearer',
            'bearerFormat': 'JWT',
          },
        },
      },
    };

    return spec;
  }

  /// Returns the spec as a pretty-printed JSON string.
  String toJson() => const JsonEncoder.withIndent('  ').convert(generate());
}

/// Converts a shelf_router path (e.g. `/users/<id>`) to OpenAPI format (`/users/{id}`).
String toOpenApiPath(String path) =>
    path.replaceAllMapped(RegExp(r'<(\w+)>'), (m) => '{${m[1]}}');

// Private alias used inside this file.
String _toOpenApiPath(String path) => toOpenApiPath(path);

/// Extracts path parameter names from a shelf_router path.
List<String> _extractPathParams(String path) =>
    RegExp(r'<(\w+)>').allMatches(path).map((m) => m[1]!).toList();

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
