/// Describes a single path parameter for OpenAPI documentation.
///
/// Path parameters found in the route path (`/users/<id>`) are documented
/// automatically as strings; declare a [PathParamSpec] to give them a real
/// type and description:
///
/// ```dart
/// ApiRoute(
///   method: ApiMethod.get,
///   path: '/users/<id>',
///   pathParams: [PathParamSpec('id', type: 'integer', description: 'User id')],
///   typedHandler: getUser,
/// )
/// ```
class PathParamSpec {
  final String name;

  /// JSON Schema type: `'string'`, `'integer'`, `'number'`, or `'boolean'`.
  final String type;

  final String? description;

  const PathParamSpec(this.name, {this.type = 'string', this.description});

  Map<String, dynamic> toOpenApiParameter() => {
    'name': name,
    'in': 'path',
    'required': true,
    if (description != null) 'description': description,
    'schema': {'type': type},
  };
}
