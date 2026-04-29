/// Describes a single query parameter for OpenAPI documentation.
///
/// Add these to [ApiRoute.queryParams] and they appear in the generated spec
/// under `parameters` with `in: query`.
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
class QueryParamSpec {
  final String name;

  /// JSON Schema type: `'string'`, `'integer'`, `'number'`, or `'boolean'`.
  final String type;

  final bool required;
  final String? description;
  final dynamic defaultValue;

  const QueryParamSpec(
    this.name, {
    this.type = 'string',
    this.required = false,
    this.description,
    this.defaultValue,
  });

  Map<String, dynamic> toOpenApiParameter() {
    final schema = <String, dynamic>{'type': type};
    if (defaultValue != null) schema['default'] = defaultValue;

    return {
      'name': name,
      'in': 'query',
      'required': required,
      if (description != null) 'description': description,
      'schema': schema,
    };
  }
}
