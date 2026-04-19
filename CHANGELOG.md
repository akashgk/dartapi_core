## 0.0.13
- Add `rateLimitMiddleware` — token-bucket rate limiter keyed by IP (or custom key); returns 429 with `Retry-After` and `X-RateLimit-*` headers
- Add `requestIdMiddleware` — attaches `X-Request-Id` to every request/response; propagates existing IDs; stores ID in `request.context['requestId']`
- Add `compressionMiddleware` — gzip-compresses responses above a configurable threshold when client sends `Accept-Encoding: gzip`

## 0.0.12
- Improve README: update version snippet, improve formatting

## 0.0.11
- Fix type-mismatch error message in `verifyKey`: now uses friendly JSON type names (`string`, `integer`, `number`, `boolean`) instead of Dart type names

## 0.0.10
- Swagger UI: `bearerAuth` security scheme is now always present in the spec so the Authorize button always appears
- Swagger UI: `persistAuthorization: true` — entered tokens survive page refreshes (stored in localStorage)

## 0.0.9
- Add `OpenApiGenerator` — generates an OpenAPI 3.0 spec from a list of `ApiRoute`s
- Add `DocsController` — serves `GET /openapi.json`, `GET /docs` (Swagger UI), `GET /redoc` (ReDoc)
- Add `SecurityScheme` enum with `bearer` value; `ApiRoute` now accepts `security: [SecurityScheme.bearer]`
- Add `contentType` field on `ApiRoute` (default `'application/json'`); used for HTML doc routes
- Add tests for all new OpenAPI types (23 additional tests)

## 0.0.8
- Expand test suite: comprehensive tests for `ApiRoute`, `RequestExtensions` (pathParam/queryParam), `MapExtensions`, and `globalExceptionMiddleware`

## 0.0.7
- Add `pathParam<T>()` extension on `Request` for typed path parameter extraction
- Add `queryParam<T>()` extension on `Request` for typed query parameter extraction with optional default values
- Add `statusCode` field on `ApiRoute` (default `200`) for custom success response codes (e.g. 201, 204)
- Add `globalExceptionMiddleware` for app-level exception handling

## 0.0.6
- Add `ApiException` class for returning specific HTTP error status codes from handlers and validators
- Fix `FormatException` (malformed JSON body) now returns 400 Bad Request instead of 500
- Fix validation errors from `verifyKey()` now return 422 Unprocessable Entity instead of 500
- `ApiException` is exported from the package

## 0.0.5
- Improved Logging

## 0.0.4
- Improve code documentation

## 0.0.3
- Add Email Validator
## 0.0.2
- Change License
- Add Middelware
- Add Validators
- Enhance Key Verification with Validators

## 0.0.1
- Initial version.
