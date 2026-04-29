## 0.1.5

**Milestone 2 — OpenAPI Spec Quality.**

- Add `QueryParamSpec` — describes a query parameter for OpenAPI docs (`name`, `type`, `required`, `description`, `defaultValue`). Export from barrel.
- Add `queryParams` field to `ApiRoute` — accepts `List<QueryParamSpec>`. Query params now appear under `parameters` with `in: query` in the generated spec alongside path params.
- Add `schemas` parameter to `OpenApiGenerator` — a `Map<String, Map<String, dynamic>>` of named schemas emitted under `components/schemas`. Routes can reference them with `{'\$ref': '#/components/schemas/Name'}`.
- Add `EnumValidator<T>(List<T> values)` — validates a closed value set; `toSchemaProperties()` emits `{enum: [...]}`. Export from barrel.
- Add array type support to `Field<T>`:
  - `Field<List<String>>` / `Field<List<int>>` / etc. now produce `jsonType: 'array'`.
  - New `arrayItemType` property auto-derived from the generic element type.
  - `FieldSet.toJsonSchema()` emits `items: {type: ...}` for array fields.
- 30 new tests in `test/openapi_spec_quality_test.dart` (545 total).

## 0.1.4

**Milestone 1 — Schema-Validation Sync (`FieldSet`).**

- Add `Field<T>` — describes a single DTO field: Dart type (mapped to JSON Schema `type`), `required` flag, validators list, optional `example` and `description`.
- Add `FieldSet` — a declarative map of `Field`s that provides:
  - `validate(Map<String, dynamic> json)` — collects ALL field errors before throwing a single `ValidationException`, replacing the need for manual `validateAll` boilerplate.
  - `toJsonSchema()` — derives a complete OpenAPI-compatible JSON Schema (`type: object`, `properties`, `required` array, `nullable` for optional fields) directly from the field declarations.
- Add `toSchemaProperties()` to every built-in validator so schema constraints come from the same source as validation rules:
  - `EmailValidator` → `{format: email}`. Constructor message is now optional (default: `'Invalid email address'`).
  - `MinLengthValidator(n)` → `{minLength: n}`
  - `MaxLengthValidator(n)` → `{maxLength: n}`
  - `NotEmptyValidator` → `{minLength: 1}`
  - `RangeValidator(min, max)` → `{minimum, maximum}`
  - `PatternValidator` → `{pattern}`
  - `UrlValidator` → `{format: uri}`
- Export `Field` and `FieldSet` from the `dartapi_core` barrel.
- 37 new tests in `test/field_set_test.dart` (515 total).

## 0.1.3

- Add comprehensive Books API example (`example/dartapi_core_example.dart`) demonstrating `DartAPI`, `ServiceRegistry`, `JwtService`, `authMiddleware`, `InMemoryTokenStore`, `BaseController`, `ApiRoute`, `InlineController`, `Pagination`, `PaginatedResponse`, `ApiException`, background tasks, per-route caching, health check, Prometheus metrics, and Swagger UI — all in a single runnable file.

## 0.1.2

**Milestone 4 — dependency injection via `ServiceRegistry`.**

- Add `ServiceRegistry` — type-safe service locator with lazy-singleton instantiation and circular dependency detection.
  - `register<T>(T Function(ServiceRegistry))` — lazy singleton factory; factory receives the registry to resolve sub-deps.
  - `registerSingleton<T>(T instance)` — eager singleton (pre-built instance).
  - `get<T>()` — resolves and caches on first call; throws `StateError` for unregistered types or circular deps.
  - `isRegistered<T>()`, `unregister<T>()`, `clear()`.
  - Circular dependency detected at resolution time with a full chain in the error message (e.g. `A → B → A`).
  - Registry is usable again after catching a circular dependency error.
- Wire `ServiceRegistry` into `DartAPI` — convenience methods `app.register<T>()`, `app.registerSingleton<T>()`, `app.get<T>()`, `app.isRegistered<T>()`, `app.registry`.
- 43 new tests in `test/service_registry_test.dart` covering all registration modes, error paths, circular deps, type safety, and `DartAPI` integration.
- Full suite: **478 tests passing**.

## 0.1.1

**Milestone 2 — auth merged in.**

- Merge all of `dartapi_auth` into `dartapi_core/lib/src/auth/`: `JwtService` (HS256 + RS256), `authMiddleware`, `apiKeyMiddleware`, `TokenStore`, `InMemoryTokenStore`, `TokenHelpers`.
- Add `dart_jsonwebtoken ^3.4.1` as a package dependency.
- Add 70 tests in `test/auth_test.dart` covering `InMemoryTokenStore`, `JwtService` (HS256 + RS256, revocation, rotation, JTI uniqueness), `authMiddleware`, `apiKeyMiddleware`, and `TokenHelpers`.

## 0.1.0

**Framework extraction (Milestone 1) — dartapi_core is now a standalone framework.**

- Add `DartAPI` class — the central application class with opt-in middleware (`enableCompression`, `enableBackgroundTasks`, `enableTimeout`, `enableRateLimit`, `enableMetrics`, `enableHealthCheck`, `enableDocs`) and lifecycle hooks (`onStartup`, `onShutdown`). No longer requires the CLI to use.
- Add `RouterManager` — registers `BaseController` instances with a Shelf `Router`; collects all `ApiRoute`s for OpenAPI generation.
- Add `InlineController` — define routes inline without creating a dedicated controller class.
- Add `AppConfig` — convenience `EnvConfig` subclass with common fields (port, debug, logLevel, database, JWT, CORS); extend to add project-specific fields.
- Add `loadEnvFile` / `mergeEnv` — `.env` file parsing utilities.
- Add `shelf_router` and `shelf_cors_headers` as package dependencies.

## 0.0.27
- Upgrade `lints` from `^5.0.0` to `^6.1.0`; fix `unnecessary_underscores` lint in tests (`__` → `_`)

## 0.0.26
- Fix `compressionMiddleware`: responses below the compression threshold had their body stream silently consumed and then returned unmodified — shelf would throw "read method can only be called once" when it tried to send the response. Now rebuilds the response with the already-buffered bytes via `response.change(body: bytes)`.

## 0.0.25
- `ApiRoute` handler now passes pre-built `shelf.Response` objects through unchanged — enables SSE (`sseResponse()`) and file-download handlers to be used with `typedHandler`

## 0.0.24
- Add `DartApiTestClient` — in-process test client that calls a Shelf `Handler` directly (no TCP socket); exposes `get`, `post`, `put`, `delete`, `patch` and `TestResponse` with `.json<T>()`
- Add `LogFormat` enum (`text` | `json`) to `loggingMiddleware` — JSON mode emits structured log lines with `timestamp`, `level`, `method`, `path`, `status`, `duration_ms`, and `request_id` (when `requestIdMiddleware` has run)
- Add `metricsMiddleware()` — records `http_requests_total` and `http_request_duration_seconds` histograms per `(method, path, status)` in a singleton `MetricsRegistry`
- Add `MetricsController` — exposes `GET /metrics` in Prometheus text format (0.0.4); register via `app.enableMetrics()`

## 0.0.23
- Add `cacheTtl: Duration?` to `ApiRoute` — opt-in per-route response caching without touching global middleware
- Add `ApiRoute.effectiveMiddlewares` getter — returns `[cacheMiddleware(ttl: cacheTtl), ...middlewares]` when `cacheTtl` is set; used by `RouterManager`
- Update `cacheMiddleware` docstring with per-route usage examples

## 0.0.22
- Add `ValidationException` — carries a list of `{field, message}` errors for multi-field validation failures
- Add `Map.validateAll(fields)` — runs all field validations, collects every failure, then throws `ValidationException` with the full list (instead of stopping at the first error)
- `ApiRoute` handler now catches `ValidationException` before `ApiException` and returns `{"errors": [...]}` with status 422

## 0.0.21
- Add `timeoutMiddleware(Duration)` — returns 408 if handler exceeds the timeout
- Fix: `null` handler result now returns 204 No Content instead of throwing a 500
- Improve `loggingMiddleware` output: `[timestamp] METHOD /path STATUS 12ms` — removed emoji, added response duration

## 0.0.20
- Fix: `_serialize` now handles `bool` and `num` responses — returning a `bool` from a handler no longer throws a 500 "Unable to serialize" error

## 0.0.19
- Add `test/base_controller_test.dart` — routes getter, webSocketRoutes default, route callability
- Add `test/logging_middleware_test.dart` — pass-through behaviour, method coverage, pipeline composition
- Extend `test/api_route_test.dart` — per-route middleware: ordering, short-circuit, header injection

## 0.0.18
- Add `EnvConfig` base class — typed env var access (`env`, `envInt`, `envDouble`, `envBool`) with injectable `environment` map for testing
- Add `MissingEnvException` and `InvalidEnvException`
- Add `HealthController` — exposes `GET /health` returning `{"status":"ok","uptime":"..."}` 

## 0.0.17
- Fix: use super parameters in `NotEmptyValidator` and `UrlValidator` (linter cleanup)

## 0.0.16
- Add `MinLengthValidator`, `MaxLengthValidator`, `NotEmptyValidator`, `RangeValidator<T extends num>`, `PatternValidator`, `UrlValidator`
- Add `Pagination` — extracts `?page` and `?limit` from a request with clamping; computes `offset`
- Add `PaginatedResponse` — `Serializable` wrapper that includes a `meta` block (`page`, `limit`, `total`, `totalPages`, `hasNext`, `hasPrev`)
- Add `SseEvent` and `sseResponse()` for Server-Sent Events streaming

## 0.0.15
- Add `header<T>()` extension on `Request` for typed header extraction (case-insensitive)
- Add `CookieRequestExtensions` — `request.cookies` map and `request.cookie(name)` for reading cookies
- Add `setCookie()` helper for attaching `Set-Cookie` headers to responses (supports `maxAge`, `path`, `domain`, `sameSite`, `httpOnly`, `secure`)
- Add `cacheMiddleware` — in-memory GET response cache with configurable TTL and custom key extractor; adds `X-Cache: HIT/MISS` headers

## 0.0.14
- Add `multipartFiles()`, `file()`, `formFields()` extensions on `Request` for `multipart/form-data` parsing
- Add `UploadedFile` with `bytes`, `filename`, `contentType`, `text`, and `isFile`
- Add `BackgroundTaskQueue`, `backgroundTaskMiddleware()`, and `Request.backgroundTasks` for post-response async work
- Add `WebSocketRoute` for WebSocket endpoints alongside HTTP routes
- `BaseController` now has `webSocketRoutes` (default empty list)
- New dependencies: `mime`, `shelf_web_socket`, `web_socket_channel`

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
