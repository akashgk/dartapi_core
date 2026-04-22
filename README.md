# dartapi_core

Core utilities for building typed, structured REST APIs in Dart — routing, validation, middleware, and OpenAPI documentation.

Part of the [DartAPI](https://pub.dev/packages/dartapi) ecosystem.

---

## Installation

```yaml
dependencies:
  dartapi_core: ^0.0.11
```

---

## Routing

Define endpoints with `ApiRoute<Input, Output>`. The framework handles request parsing, response serialization, and error mapping automatically.

```dart
class UserController extends BaseController {
  @override
  List<ApiRoute> get routes => [
    ApiRoute<void, List<String>>(
      method: ApiMethod.get,
      path: '/users',
      typedHandler: getAllUsers,
      summary: 'Get all users',
    ),
    ApiRoute<UserDTO, UserDTO>(
      method: ApiMethod.post,
      path: '/users',
      statusCode: 201,
      typedHandler: createUser,
      dtoParser: UserDTO.fromJson,
    ),
  ];
}
```

---

## Path Parameters

Use `request.pathParam<T>(name)` to extract typed path parameters. Shelf Router populates these from route patterns like `/users/<id>`.

```dart
ApiRoute<void, User>(
  method: ApiMethod.get,
  path: '/users/<id>',
  typedHandler: (request, _) async {
    final id = request.pathParam<int>('id');
    return userService.findById(id);
  },
)
```

Supported types: `String`, `int`, `double`, `bool`. Throws `ApiException(400)` if the param is missing or cannot be converted.

---

## Query Parameters

Use `request.queryParam<T>(name, defaultValue: ...)` to extract typed query parameters.

```dart
ApiRoute<void, List<Product>>(
  method: ApiMethod.get,
  path: '/products',
  typedHandler: (request, _) async {
    final page = request.queryParam<int>('page', defaultValue: 1);
    final limit = request.queryParam<int>('limit', defaultValue: 20);
    final search = request.queryParam<String>('q');
    return productService.list(page: page!, limit: limit!, search: search);
  },
)
```

Returns `null` (or `defaultValue`) when the parameter is absent.

---

## Custom Response Status Codes

Set `statusCode` on any route to override the default `200 OK`:

```dart
ApiRoute(method: ApiMethod.post,   path: '/users',      statusCode: 201, ...)
ApiRoute(method: ApiMethod.delete, path: '/users/<id>', statusCode: 204, ...)
```

---

## Request Validation

Use `verifyKey<T>()` on request body maps to extract fields with type checking and optional validators:

```dart
factory UserDTO.fromJson(Map<String, dynamic> json) {
  return UserDTO(
    name:  json.verifyKey<String>('name'),
    age:   json.verifyKey<int>('age'),
    email: json.verifyKey<String>('email', validators: [
      EmailValidator('Invalid email'),
    ]),
  );
}
```

Throws `ApiException(422)` on missing fields, wrong types, or failed validation. Type errors report friendly names (`string`, `integer`, `boolean`) rather than Dart type names.

### Built-in validators

| Validator | Description |
|-----------|-------------|
| `EmailValidator(message)` | Validates email format |

### Custom validators

```dart
class MinLengthValidator extends Validators<String> {
  final int min;
  MinLengthValidator(this.min) : super('Must be at least $min characters');

  @override
  bool validate(dynamic value) => (value as String).length >= min;
}
```

---

## Error Handling

Throw `ApiException(statusCode, message)` from any handler or validator to return a specific HTTP error:

```dart
throw ApiException(404, 'User not found');
throw ApiException(422, 'Invalid input');
throw ApiException(401, 'Unauthorized');
```

The framework catches these automatically and returns a JSON response with the correct status code.

---

## Middleware

### Logging (built-in)

```dart
Pipeline().addMiddleware(loggingMiddleware())
```

Logs method, URI, and response status for every request.

### Global exception handler

Catch any unhandled exception and return a controlled error response:

```dart
Pipeline()
  .addMiddleware(globalExceptionMiddleware(
    onError: (error, stackTrace) {
      if (error is DatabaseException) return ApiException(503, 'Database unavailable');
      return ApiException(500, 'Something went wrong');
    },
  ))
  .addMiddleware(loggingMiddleware())
  .addHandler(router.handler)
```

### Per-route middleware

```dart
ApiRoute(
  middlewares: [authMiddleware(jwtService)],
  ...
)
```

### Rate limiting

Token-bucket limiter keyed by client IP by default. Returns `429 Too Many Requests` with `Retry-After` and `X-RateLimit-*` headers when the bucket is empty.

```dart
Pipeline()
  .addMiddleware(rateLimitMiddleware(
    maxRequests: 100,
    window: Duration(minutes: 1),
  ))
  .addHandler(router.handler)
```

Key by user ID or API key instead of IP:

```dart
rateLimitMiddleware(
  maxRequests: 1000,
  keyExtractor: (req) =>
      (req.context['user'] as Map?)?['sub'] as String? ?? 'anonymous',
)
```

### Request ID

Attaches `X-Request-Id` to every request/response. Propagates an existing ID from the client if present; otherwise generates a new random one. The ID is also stored in `request.context['requestId']`.

```dart
Pipeline()
  .addMiddleware(requestIdMiddleware())
  .addHandler(router.handler)
```

### Response compression

Gzip-compresses responses when the client sends `Accept-Encoding: gzip` and the body exceeds a configurable threshold (default 1 KB).

```dart
Pipeline()
  .addMiddleware(compressionMiddleware())           // default threshold: 1024 bytes
  .addMiddleware(compressionMiddleware(threshold: 512))
  .addHandler(router.handler)
```

---

## OpenAPI / Swagger Docs

Call `enableDocs()` after `addControllers()` to serve auto-generated documentation:

```dart
app.addControllers([userController, productController]);
app.enableDocs(title: 'My App', version: '1.0.0');
await app.start();
```

This registers three endpoints:

| Endpoint | Description |
|----------|-------------|
| `GET /openapi.json` | OpenAPI 3.0 spec |
| `GET /docs` | Swagger UI (with persistent Bearer token support) |
| `GET /redoc` | ReDoc UI |

Mark routes that require authentication so Swagger UI shows the lock icon:

```dart
ApiRoute(
  method: ApiMethod.get,
  path: '/me',
  security: [SecurityScheme.bearer],
  middlewares: [authMiddleware(jwtService)],
  typedHandler: getProfile,
)
```

Export the spec from the CLI while the server is running:

```bash
dartapi docs --out openapi.json
```

---

## File Uploads

Parse `multipart/form-data` requests using the `Request` extensions added by this package.

```dart
Future<String> uploadAvatar(Request request, void _) async {
  if (!request.isMultipart) throw ApiException(400, 'Expected multipart/form-data');

  final avatar = await request.file('avatar');
  if (avatar == null) throw ApiException(400, 'Missing file field "avatar"');

  // avatar.bytes, avatar.filename, avatar.contentType
  await saveFile(avatar.filename!, avatar.bytes);
  return 'Uploaded ${avatar.filename}';
}
```

Read plain form fields alongside files:

```dart
final fields = await request.formFields();  // Map<String, String>
final title = fields['title'] ?? '';

final parts = await request.multipartFiles(); // List<UploadedFile>
```

---

## Background Tasks

Schedule async work to run after the response has been sent (similar to FastAPI's `BackgroundTasks`). Add `backgroundTaskMiddleware()` to the pipeline once, then call `request.backgroundTasks.add(...)` from any handler.

```dart
// In pipeline setup:
Pipeline()
  .addMiddleware(backgroundTaskMiddleware())
  .addHandler(router.handler)

// In a handler:
Future<String> createUser(Request request, UserDTO? dto) async {
  request.backgroundTasks.add(() => emailService.sendWelcome(dto!.email));
  return 'User created';  // response sent immediately; email sends after
}
```

Tasks run sequentially after the response resolves. Errors in tasks are swallowed so they never affect the response.

---

## WebSocket Support

Define WebSocket endpoints in a controller alongside HTTP routes:

```dart
class ChatController extends BaseController {
  @override
  List<ApiRoute> get routes => [];

  @override
  List<WebSocketRoute> get webSocketRoutes => [
    WebSocketRoute(
      path: '/ws/chat',
      handler: (channel, _) async {
        await for (final message in channel.stream) {
          channel.sink.add('Echo: $message');
        }
      },
    ),
  ];
}
```

Apply middleware (e.g. auth) before the upgrade handshake:

```dart
WebSocketRoute(
  path: '/ws/private',
  middlewares: [authMiddleware(jwtService)],
  handler: (channel, _) { ... },
)
```

The generated `RouterManager` handles both `routes` and `webSocketRoutes` automatically.

---

## Validation

### Built-in validators

| Validator | Type | Description |
|-----------|------|-------------|
| `EmailValidator(message)` | `String` | Validates email format |
| `MinLengthValidator(n)` | `String` | At least `n` characters |
| `MaxLengthValidator(n)` | `String` | At most `n` characters |
| `NotEmptyValidator()` | `String` | Non-blank string |
| `RangeValidator<T>(min:, max:)` | `num` | Numeric range (inclusive) |
| `PatternValidator(regex, message)` | `String` | Regex match |
| `UrlValidator()` | `String` | Valid `http`/`https` URL |

```dart
factory UserDTO.fromJson(Map<String, dynamic> json) => UserDTO(
  name: json.verifyKey<String>('name', validators: [
    MinLengthValidator(2),
    MaxLengthValidator(50),
  ]),
  age: json.verifyKey<int>('age', validators: [
    RangeValidator<int>(min: 0, max: 150),
  ]),
  website: json.verifyKey<String>('website', validators: [UrlValidator()]),
);
```

---

## Pagination

`Pagination.fromRequest()` reads `?page` and `?limit`, clamps them, and computes the SQL offset:

```dart
final p = Pagination.fromRequest(request, defaultLimit: 20, maxLimit: 100);
final rows = await db.select('products', limit: p.limit, offset: p.offset);
```

Wrap results in `PaginatedResponse` for a consistent envelope:

```dart
return PaginatedResponse(data: rows, pagination: p, total: totalCount);
```

Serializes to:

```json
{
  "data": [...],
  "meta": { "page": 2, "limit": 20, "total": 150, "totalPages": 8, "hasNext": true, "hasPrev": true }
}
```

---

## Server-Sent Events

Stream events to the client with `sseResponse()`. The response sets the correct headers automatically.

```dart
ApiRoute<void, void>(
  method: ApiMethod.get,
  path: '/events',
  typedHandler: (req, _) async {
    final stream = Stream.periodic(Duration(seconds: 1), (i) =>
      SseEvent(data: 'tick $i', event: 'tick', id: '$i'));
    return sseResponse(stream.take(10));
  },
)
```

`SseEvent` fields: `data` (required), `id`, `event`, `retry`.

---

## Headers

Use `request.header<T>(name)` to extract typed request headers (case-insensitive):

```dart
final locale = request.header<String>('Accept-Language');
final version = request.header<int>('X-Api-Version', defaultValue: 1);
```

Returns `null` (or `defaultValue`) when absent. Throws `ApiException(400)` if the value cannot be cast.

---

## Cookies

Read cookies from incoming requests:

```dart
final all = request.cookies;          // Map<String, String>
final token = request.cookie('session'); // String?
```

Set cookies on a response:

```dart
return setCookie(
  Response.ok('logged in'),
  'session', tokenValue,
  maxAge: Duration(hours: 1),
  httpOnly: true,
  secure: true,
  sameSite: 'Strict',
);
```

---

## Response Caching

Cache GET responses in memory for a configurable TTL. Cached responses include `X-Cache: HIT`; cache misses include `X-Cache: MISS`. Only 200 responses are cached; POST/PUT/DELETE/PATCH bypass the cache entirely.

### Per-route caching (recommended)

Use `cacheTtl` on `ApiRoute` to opt specific routes into caching — other endpoints are unaffected:

```dart
ApiRoute(
  method: ApiMethod.get,
  path: '/products',
  cacheTtl: Duration(minutes: 10),
  typedHandler: (req, _) async => fetchProducts(),
)
```

### Global caching

To cache every GET endpoint in the app, apply `cacheMiddleware` globally in the pipeline:

```dart
Pipeline()
  .addMiddleware(cacheMiddleware(ttl: Duration(minutes: 10)))
  .addHandler(router.handler)
```

Use a custom key extractor to ignore query parameters or key by user:

```dart
cacheMiddleware(
  ttl: Duration(minutes: 5),
  keyExtractor: (req) => req.url.path,
)
```

---

## Links

- [dartapi CLI](https://pub.dev/packages/dartapi)
- [dartapi_auth](https://pub.dev/packages/dartapi_auth)
- [dartapi_db](https://pub.dev/packages/dartapi_db)
- [GitHub](https://github.com/akashgk/dartapi_core)

---

## License

BSD 3-Clause License © 2025 Akash G Krishnan
