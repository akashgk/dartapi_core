## 0.7.1

- Raise dependency floors to the current latest releases: `crypto ^3.0.7`,
  `shelf_router ^1.1.4`, `shelf_cors_headers ^0.1.5`, `test ^1.31.2`.
  No behaviour changes.

## 0.7.0

**Built-in password hashing — `PasswordHasher`.**

### New features

- **`PasswordHasher`** — salted PBKDF2-HMAC-SHA256 password hashing with no
  extra dependencies (`package:crypto` only):
  - `PasswordHasher.hash(password)` → self-describing
    `pbkdf2-sha256$<iterations>$<salt>$<hash>` string to store;
  - `PasswordHasher.verify(password, encoded)` → constant-time comparison;
    malformed input returns `false` instead of throwing;
  - parameters travel with the hash, so the iteration count (default
    100 000) can be raised later without invalidating stored hashes;
  - implementation validated against the standard PBKDF2-HMAC-SHA256
    known-answer test vector.
- Hashing is deliberately CPU-bound (~100–300 ms); for high-traffic login
  endpoints run it via `Isolate.run(...)` as documented.

Closes the gap where generated projects' auth stub compared plaintext
passwords because the framework offered no hashing primitive.

## 0.6.0

**Session-wide token revocation — `revokeAllForUser`.**

Until now the `TokenStore` could only revoke one token (`jti`) at a time, so
the documented response to refresh-token reuse ("revoke the whole session")
was not actually expressible with the framework's own APIs.

### New features

- **`JwtService.revokeAllForUser(sub)`** — invalidates every outstanding
  access *and* refresh token for a subject. Tokens issued at or before the
  revocation moment are rejected by `verifyAccessToken`/`verifyRefreshToken`;
  a fresh login afterwards works normally. The revocation entry expires on
  its own once the longest-lived token would have expired anyway.
- **`TokenStore.revokeSubject(sub, cutoffEpochSeconds:, ttl:)`** and
  **`TokenStore.subjectRevocationCutoff(sub)`** — the underlying primitives,
  with in-process default implementations on the base class. Like
  `revokeIfActive`, distributed backends (Redis, SQL) should override them
  with a shared store.
- Session-revoked refresh tokens are rejected **without** firing
  `onRefreshTokenReuse` — a dead session is not a theft signal.

### Notes

- The intended wiring, now actually possible:
  ```dart
  onRefreshTokenReuse: (payload) async {
    final sub = payload['sub'];
    if (sub is String) await jwtService.revokeAllForUser(sub);
  }
  ```
- Reminder: `InMemoryTokenStore` (including its new subject entries) is
  per-process. Behind `--isolates=N` or multiple instances, use a shared
  `TokenStore` backend — a Redis adapter is on the roadmap.

## 0.5.0

**OpenAPI overhaul — the spec now documents what the framework actually does, and the docs UI can't break under you.**

### Breaking changes

- `DocsController` now takes a lazy `routesProvider: () => routes` instead of `apiRoutes: routes`. If you only use `app.enableDocs()`, nothing changes — but `enableDocs` may now be called **before or after** `addControllers` (routes are collected on first request, removing the silent "controllers registered after enableDocs are missing from the docs" footgun).
- The spec version is now `3.0.3` (was `3.0.0`).
- The three docs routes (`/openapi.json`, `/docs`, `/redoc`) no longer appear in the generated spec.

### New features

- **`ApiRoute.requestFields: FieldSet`** — pass the same `FieldSet` that validates the request; the request body schema is derived from it. One declaration, zero drift between validation and documentation.
- **Automatic error responses.** Routes with a body parser document `422 Validation Error` and `400 Bad Request` (schemas match the real error envelopes: `{"errors":[{"field","message"}]}` and `{"error","message"}`); routes with `security` document `401 Unauthorized`. `ValidationError`/`Error` component schemas are added automatically.
- **`ApiRoute.responses: {404: ResponseSpec('Not found', schema: ...)}`** — document any additional responses; explicit entries override the automatic ones.
- **`operationId` on every operation** — explicit via `ApiRoute.operationId`, otherwise derived from method + path (`GET /users/<id>` → `get_users_by_id`). OpenAPI client generators now produce usable method names instead of garbage.
- **Typed path parameters** via `ApiRoute.pathParams: [PathParamSpec('id', type: 'integer')]`; undeclared params still default to string.
- **`SecurityScheme.apiKey`** — documents header API-key auth (lock icon in Swagger UI); header name configurable via `enableDocs(apiKeyHeader:)` to match `apiKeyMiddleware`.
- **`servers` in the spec** via `enableDocs(servers: ['https://api.example.com'])` — drives Swagger UI "Try it out" base URLs and client codegen.
- **Pinned, overridable UI assets.** Swagger UI (`5.32.8`) and ReDoc (`2.5.3`) load from jsdelivr at pinned versions instead of unpkg `@latest` — an upstream major release can no longer break `/docs` overnight. Override `swaggerUiCssUrl` / `swaggerUiJsUrl` / `redocJsUrl` to self-host for air-gapped/CSP-restricted deployments.
- **Spec caching** — `/openapi.json` is generated once and cached instead of rebuilt per request.
- Swagger UI enables `deepLinking`, `filter` (search box), and `tryItOutEnabled` by default.

## 0.4.0

**Production runtime hardening: graceful shutdown, TLS, proxy-safe rate limiting, API versioning, static files.**

### Breaking changes

- **Rate limiter no longer trusts `X-Forwarded-For` by default.** Previously the default key extractor read `X-Forwarded-For`/`X-Real-IP` unconditionally — a client could rotate fake header values to dodge the limiter, and all direct clients (no header) shared one `'unknown'` bucket, letting a single abuser throttle everyone. The default key is now the real socket IP. Behind a reverse proxy or load balancer, pass `trustProxy: true` to `enableRateLimit` / `rateLimitMiddleware` to key by the first `X-Forwarded-For` entry.
- **SIGINT/SIGTERM now drain instead of abort.** Signal-triggered shutdown previously called `stop(force: true)`, killing in-flight requests — the opposite of what a rolling deploy needs. Signals now trigger a graceful drain bounded by the new `DartAPI(shutdownGracePeriod: ...)` (default 30 s).
- **Shutdown hooks now run *after* the drain**, so a hook that closes the database can no longer break requests still completing. Previously hooks ran before the listener closed.
- **Removed deprecated `JwtService.generateRefreshToken(accessToken: ...)`** as announced in 0.3.0 — use `generateTokenPair` instead.

### New features

- **Graceful shutdown**: `stop()` stops accepting connections, waits until every in-flight response is fully written (dart:io's `close(force: false)` does not), then force-closes stragglers after `shutdownGracePeriod`.
- **TLS**: `app.start(securityContext: SecurityContext()..useCertificateChain(...)..usePrivateKey(...))` serves HTTPS natively.
- **API versioning / route prefixes**: `app.addControllers([...], prefix: '/api/v1')` prefixes every HTTP and WebSocket route and is reflected in the OpenAPI spec.
- **Static file serving**: `app.serveStatic('/public', 'web')` (built on `shelf_static`), with `defaultDocument` and `listDirectories` options.
- **`clientIp(request, trustProxy: ...)`** exported helper — spoof-safe client IP resolution for logging, custom rate-limit keys, and audit trails.
- **`app.port`** — the bound port, or `null` when not running. Combine with `start(port: 0)` to bind an ephemeral port in tests.
- `InlineController` now accepts an optional `tag:` for OpenAPI grouping, mirroring `BaseController.tag`.

## 0.3.0

**Secure token revocation and refresh rotation.**

### Breaking changes

- `JwtService.revokeToken` now **verifies the token's signature before revoking** and returns `Future<bool>` (`true` when verified and revoked). Previously it blindly base64-decoded the payload, so an attacker who learned a `jti` could revoke another user's session with a forged token.
- `TokenStore.revoke` gained a `{Duration? ttl}` parameter — the time remaining until the token's own `exp` (plus a one-minute clock-skew grace). Backends should use it to expire revocation entries (e.g. Redis `SET key 1 EX ttl`) so the store does not grow forever. Custom implementations must add the parameter.
- `TokenStore` is now an abstract **base class** with a concrete `revokeIfActive(jti, {ttl})` method — extend it rather than implement it. `revokeIfActive` atomically revokes a jti and reports whether it was still active; distributed backends should override it with an atomic operation (Redis `SET NX EX`, SQL `INSERT ... ON CONFLICT DO NOTHING`).
- `generateAccessToken` / `generateTokenPair` no longer allow caller claims to override the protected standard claims (`jti`, `iss`, `aud`, `type`, `iat`, `exp`).

### Deprecations

- `generateRefreshToken({required String accessToken})` is deprecated — deriving a long-lived refresh token from a short-lived access token allows a stolen access token to be upgraded. Use `generateTokenPair` instead. Will be removed in 0.4.0.

### New features

- `generateTokenPair({required claims})` — issues a matched access/refresh `TokenPair` directly from claims; the recommended API for login and refresh endpoints.
- `onRefreshTokenReuse` callback on `JwtService` — fires when an already-rotated refresh token is presented again (the classic token-theft signal per the OAuth 2.0 Security BCP), so applications can terminate the whole session.
- Refresh rotation is now **atomic**: `verifyRefreshToken` uses `TokenStore.revokeIfActive`, so under concurrent use of the same refresh token exactly one caller succeeds (fixes a check-then-revoke race).
- `InMemoryTokenStore` prunes expired revocation entries automatically — memory is bounded by the number of tokens revoked within one token lifetime.

### Fixes

- `example/dartapi_core_example.dart` refresh endpoint now returns a full new token pair — previously it consumed the single-use refresh token but only returned a new access token, stranding the client.

## 0.2.0

**Bug fixes, hardening, and API polish.**

### Breaking changes

- `authMiddleware` now returns `401 Unauthorized` with a `WWW-Authenticate: Bearer` header when the token is missing or invalid (was `403 Forbidden`), matching RFC 6750.
- Unhandled exceptions in route handlers now return a generic `{"error":"Internal Server Error"}` body instead of leaking the exception message to the client. The full error and stack trace are logged server-side.
- `queryParam<bool>` / `pathParam<bool>` / `header<bool>` now accept only `true`/`false`/`1`/`0` (case-insensitive) and throw `ApiException` 400 for anything else (previously any non-`'true'` value silently became `false`).

### Bug fixes

- Fix response serialization for `List<Serializable>` and `Serializable` objects nested inside maps/lists — `typedHandler` can now return `Future<List<UserDTO>>` directly.
- Fix `globalExceptionMiddleware` producing invalid JSON when the error message contains quotes or backslashes.
- Fix `requestIdMiddleware` and `rateLimitMiddleware` corrupting multi-value response headers (multiple `Set-Cookie` values were joined with commas).
- Fix `setCookie` — multiple cookies are now sent as separate `Set-Cookie` header lines instead of being joined with a newline.
- Fix `cacheMiddleware` caching responses that carry `Set-Cookie` — one client's session cookie could previously be replayed to other clients.
- Fix `rateLimitMiddleware` unbounded memory growth — expired buckets are now pruned periodically.
- Fix `FieldSet.validate` throwing a cast error (HTTP 500) when a field has the wrong JSON type — now reports a proper 422 field error (`must be of type integer`).
- Fix `HealthController` returning 500 when a health check throws — a throwing check now marks the service `degraded` with the error message.
- Fix multipart parsing when the boundary parameter is quoted (`boundary="..."`).
- Fix JSON array request bodies causing a 500 when a DTO parser expects an object — now returns 400.
- Fix `204` responses missing the `Deprecation` header on deprecated routes.
- `compressionMiddleware` now sets `Vary: Accept-Encoding` on compressed responses.

### Improvements

- `DartAPI.start()` accepts an `address` parameter (default `0.0.0.0`).
- New `DartAPI.stop({bool force})` — programmatic graceful shutdown: cancels signal watchers, runs `onShutdown` hooks, then closes the server. Safe to call multiple times.
- New `DartAPI.configureLogging(format:, excludePaths:)` — switch the built-in request logging to JSON or silence noisy paths.
- `JwtService` now parses RSA PEM keys once and caches them; token id generation reuses a single `Random.secure()` instance.
- `RangeValidator` asserts that at least one bound is provided and no longer produces a "Must be at most null" message.

## 0.1.9

**New features.**

- Add `bodySizeLimitMiddleware({int maxBytes})` — rejects requests whose `Content-Length` exceeds the limit with `413 Payload Too Large` before the body is read. Default 1 MB. Enable via `app.enableBodySizeLimit()`.
- Add `securityHeadersMiddleware({...})` — adds `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `X-XSS-Protection`, `Permissions-Policy`, and optional `Content-Security-Policy` / `Strict-Transport-Security` headers. Enable via `app.enableSecurityHeaders()`.
- Add `excludePaths` parameter to `loggingMiddleware` — paths with any matching prefix are silently skipped (e.g. `excludePaths: ['/health', '/metrics']`).
- Add `HealthCheckResult` class and `checks` parameter to `HealthController` / `app.enableHealthCheck()` — run named async health checks; `status` becomes `"degraded"` if any check is unhealthy.
- Add `deprecated` flag to `ApiRoute` — emits `deprecated: true` in the OpenAPI spec and adds a `Deprecation: true` response header (RFC 8594).
- Replace threshold-based cache sweep with proper LRU eviction in `cacheMiddleware` — oldest unused entry is evicted when `maxEntries` (default 500) is reached; cache hits promote the entry to most-recently-used.
- Add `app.enableBodySizeLimit()` and `app.enableSecurityHeaders()` convenience methods on `DartAPI`.

## 0.1.8

**Bug fixes and hardening.**

- Fix `cacheMiddleware` memory leak — expired entries are now removed on access and a sweep evicts all stale entries when the cache exceeds 500 keys, preventing unbounded memory growth in long-running servers.
- Fix `HealthController` uptime — replaced `DateTime.now().difference(startedAt)` with `Stopwatch.elapsed` so reported uptime is immune to system clock adjustments.
- Fix `JwtService._isValidPayload` — type-checks every standard claim (`sub`, `jti`, `iss`, `aud`, `type` must be `String`; `iat`, `exp` must be `int`), preventing silent cast errors when a malformed token carries wrong-typed claims.
- Fix `EmailValidator` regex — now accepts `+`, `%`, `_` and other RFC 5321 characters in the local part (e.g. `user+tag@example.com`).
- Fix `dart analyze` — move `// ignore: prefer_initializing_formals` comments to the correct lines in `JwtService` constructor initialisers so the linter actually suppresses them.
- Dependency upgrades: `test` 1.31.0 → 1.31.1, `test_api` 0.7.11 → 0.7.12, `test_core` 0.6.17 → 0.6.18, `matcher` 0.12.19 → 0.12.20, `analyzer` 12.1.0 → 13.0.0, `vm_service` 15.1.0 → 15.2.0.

## 0.1.7

**Milestone 5 — OpenAPI Tags.**

- Add `tags` field to `ApiRoute` — a `List<String>` that appears under `tags` in the generated OpenAPI operation object. Routes with the same tag are grouped together in Swagger UI and ReDoc.
- Add `withTags(List<String>)` method to `ApiRoute` — returns a copy of the route with new tags (all other fields unchanged). Used internally by `RouterManager`.
- Add `tag` getter to `BaseController` — override in a subclass to automatically apply one tag to every route that declares no explicit tags (e.g. `String? get tag => 'Users';`). Routes that already have explicit tags are not affected.
- Update `RouterManager.registerController()` — stamps the controller's `tag` onto routes with an empty `tags` list before collecting them for the spec generator.
- Add `tagDescriptions` parameter to `OpenApiGenerator`, `DocsController`, and `enableDocs()` — a `Map<String, String>` of tag name → description. These appear in the top-level `tags` array of the OpenAPI spec, adding human-readable descriptions under each group heading in Swagger UI and ReDoc.
- `OpenApiGenerator.generate()` now emits `tags` on each operation when the route has tags and a deduplicated top-level `tags` array (with optional descriptions) when any route or `tagDescriptions` entry declares a tag.
- Update `rest_api` example — `BookController` overrides `tag => 'Books'`; `enableDocs()` passes `tagDescriptions: {'Books': 'CRUD operations for the book catalogue'}`.
- 21 new tests in `test/openapi_tags_test.dart` (566 total).

## 0.1.6

**Milestone 3 — Example Projects.**

- Add `example/minimal/` — one-file server with `InlineController`, health check, and Swagger UI; compiles to a standalone executable.
- Add `example/rest_api/` — full CRUD Books API: `FieldSet` DTOs, JWT auth, `ServiceRegistry`, `QueryParamSpec`, `$ref` schemas, `DartApiTestClient` tests (14 tests). Demonstrates every Milestone 1–2 feature end-to-end.
- Add `example/standalone_no_cli/` — annotated starter project equivalent to `dartapi create --minimal`; explains every file and every decision.
- Add `schemas` parameter to `enableDocs()` — pass `Map<String, Map<String, dynamic>>` of named schemas; forwarded to `DocsController` and `OpenApiGenerator` so `components/schemas` appears in the spec without constructing the generator manually.
- Add `schemas` field to `DocsController` — enables named schemas when constructing the controller directly without `DartAPI`.
- Update `README.md` — lead with "Getting Started in 5 Minutes (No CLI)", examples table, updated validators table with `EnumValidator`, `QueryParamSpec` and `$ref` OpenAPI docs.

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
