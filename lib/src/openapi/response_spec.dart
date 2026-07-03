/// Documents one non-default response of an [ApiRoute] in the OpenAPI spec.
///
/// The route's own [ApiRoute.statusCode] (plus the automatic 422/400 for
/// routes with a body parser and 401 for routes with `security`) is
/// documented for free — use `responses` for everything else:
///
/// ```dart
/// ApiRoute(
///   method: ApiMethod.get,
///   path: '/users/<id>',
///   responses: {
///     404: ResponseSpec('User not found'),
///     409: ResponseSpec('Conflict', schema: {r'$ref': '#/components/schemas/Error'}),
///   },
///   typedHandler: getUser,
/// )
/// ```
class ResponseSpec {
  /// Human-readable description shown in Swagger UI / ReDoc.
  final String description;

  /// Optional JSON schema of the response body (inline map or `$ref`).
  final Map<String, dynamic>? schema;

  const ResponseSpec(this.description, {this.schema});

  Map<String, dynamic> toOpenApiResponse() => {
    'description': description,
    if (schema != null)
      'content': {
        'application/json': {'schema': schema},
      },
  };
}
