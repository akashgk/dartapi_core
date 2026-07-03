/// Defines security schemes that can be applied to an [ApiRoute].
///
/// These are used when generating an OpenAPI specification to indicate
/// which authentication method is required for a route.
///
/// ```dart
/// ApiRoute(
///   method: ApiMethod.get,
///   path: '/me',
///   security: [SecurityScheme.bearer],
///   typedHandler: getProfile,
/// )
/// ```
enum SecurityScheme {
  /// HTTP Bearer token authentication (e.g. JWT).
  bearer,

  /// Static API key sent in a request header (default `X-API-Key`, matching
  /// `apiKeyMiddleware`). Configure the header name via
  /// `enableDocs(apiKeyHeader: ...)`.
  apiKey,
}
