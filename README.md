# dartapi_core

A framework for building typed, structured REST APIs in Dart — routing, validation, middleware, dependency injection, JWT auth, OpenAPI documentation, and full server lifecycle. Use it directly or via the [dartapi CLI](https://pub.dev/packages/dartapi).

---

## Getting Started in 5 Minutes (No CLI)

```yaml
dependencies:
  dartapi_core: ^0.1.6
```

```dart
import 'package:dartapi_core/dartapi_core.dart';

void main() async {
  final app = DartAPI(appName: 'my_api');

  app.addControllers([
    InlineController([
      ApiRoute(
        method: ApiMethod.get,
        path: '/hello',
        summary: 'Say hello',
        typedHandler: (req, _) async => {'message': 'Hello, World!'},
      ),
    ]),
  ]);

  app.enableDocs(title: 'My API', version: '1.0.0');
  app.enableHealthCheck();
  await app.start(port: 8080);
}
```

Run with `dart run bin/main.dart` — open `http://localhost:8080/docs` for Swagger UI.

## Examples

Three runnable examples live in [`example/`](example/):

| Example | Description |
|---|---|
| [`example/minimal/`](example/minimal/) | One file, one route — the smallest possible server |
| [`example/rest_api/`](example/rest_api/) | Full CRUD with JWT auth, FieldSet DTOs, ServiceRegistry, tests |
| [`example/standalone_no_cli/`](example/standalone_no_cli/) | Annotated starter project (equivalent to `dartapi create --minimal`) |

Each example has its own `pubspec.yaml` and `README.md` with copy-paste run instructions.

---

## Installation

```yaml
dependencies:
  dartapi_core: ^0.1.6
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

For one-off routes without a dedicated controller class, use `InlineController`:

```dart
app.addControllers([
  InlineController([
    ApiRoute<void, Map<String, String>>(
      method: ApiMethod.get,
      path: '/ping',
      typedHandler: (req, _) async => {'status': 'ok'},
    ),
  ]),
]);
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

### Single-field validation

Use `verifyKey<T>()` on request body maps to extract fields with type checking and optional validators:

```dart
factory UserDTO.fromJson(Map<String, dynamic> json) {
  return UserDTO(
    name:  json.verifyKey<String>('name', validators: [
      MinLengthValidator(2), MaxLengthValidator(50),
    ]),
    age:   json.verifyKey<int>('age'),
    email: json.verifyKey<String>('email', validators: [EmailValidator()]),
  );
}
```

Throws `ApiException(422)` on the first failing field.

### Multi-field validation (`validateAll`)

Use `validateAll` to collect errors from every field before throwing — the client sees all problems at once instead of fixing them one at a time:

```dart
factory BookDTO.fromJson(Map<String, dynamic> json) {
  json.validateAll({
    'title':  () => json.verifyKey<String>('title',  validators: [NotEmptyValidator(), MaxLengthValidator(200)]),
    'author': () => json.verifyKey<String>('author', validators: [NotEmptyValidator()]),
    'year':   () => json.verifyKey<int>('year'),
  });

  return BookDTO(
    title:  json['title']  as String,
    author: json['author'] as String,
    year:   json['year']   as int,
  );
}
```

Throws a single `ApiException(422)` listing every invalid field.

### `FieldSet` — declare fields once, get validation + schema

`FieldSet` is the recommended way to define DTOs. Declare fields once and get runtime validation and an OpenAPI JSON Schema from the same source — no drift between rules and docs.

```dart
class CreateUserDTO {
  static final fields = FieldSet({
    'name':  Field<String>(validators: [NotEmptyValidator(), MaxLengthValidator(100)], example: 'Alice'),
    'email': Field<String>(validators: [EmailValidator()]),
    'age':   Field<int>(required: false, validators: [RangeValidator(min: 0, max: 150)]),
    'role':  Field<String>(validators: [EnumValidator(['user', 'admin'])]),
    'tags':  Field<List<String>>(),  // emits {type: array, items: {type: string}}
  });

  static Map<String, dynamic> get schema => fields.toJsonSchema();

  factory CreateUserDTO.fromJson(Map<String, dynamic> json) {
    fields.validate(json); // collects ALL field errors, throws ValidationException
    return CreateUserDTO(...);
  }
}
```

Use the schema in OpenAPI:

```dart
app.enableDocs(
  title: 'My API',
  schemas: {'CreateUserDTO': CreateUserDTO.schema},
);
// then on a route:
ApiRoute(requestSchema: {r'$ref': '#/components/schemas/CreateUserDTO'}, ...)
```

### Built-in validators

Each validator also implements `toSchemaProperties()` so its constraints appear in the generated OpenAPI spec automatically.

| Validator | Type | Schema output |
|-----------|------|---------------|
| `EmailValidator([msg])` | `String` | `{format: email}` |
| `MinLengthValidator(n)` | `String` | `{minLength: n}` |
| `MaxLengthValidator(n)` | `String` | `{maxLength: n}` |
| `NotEmptyValidator()` | `String` | `{minLength: 1}` |
| `RangeValidator<T>(min:, max:)` | `num` | `{minimum, maximum}` |
| `PatternValidator(regex, msg)` | `String` | `{pattern: regex.pattern}` |
| `UrlValidator()` | `String` | `{format: uri}` |
| `EnumValidator<T>(values, [msg])` | any | `{enum: [...]}` |

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

## Dependency Injection

`ServiceRegistry` is built into `DartAPI`. Registrations are lazy singletons — the factory runs on first `get<T>()`, is cached, and dependencies are resolved automatically.

```dart
final app = DartAPI();

app.register<UserRepository>((_) => InMemoryUserRepository());
app.register<JwtService>(
  (r) => JwtService(
    accessTokenSecret: 'secret',
    refreshTokenSecret: 'refresh-secret',
    issuer: 'my-app',
    audience: 'api-users',
    tokenStore: r.get<InMemoryTokenStore>(),
  ),
);
app.register<UserService>((r) => UserService(r.get<UserRepository>()));

// Resolve when wiring controllers
app.addControllers([
  UserController(service: app.get<UserService>()),
]);
```

Use `registerSingleton<T>(instance)` to register an already-constructed instance:

```dart
app.registerSingleton<AppConfig>(AppConfig(environment: env));
```

Circular dependencies are detected at resolution time with a full chain in the error message (e.g. `A → B → A`).

---

## JWT Authentication

`JwtService`, `authMiddleware`, `InMemoryTokenStore`, and `apiKeyMiddleware` are all included in `dartapi_core` — no separate auth package needed.

### Setup

```dart
final jwt = JwtService(
  accessTokenSecret: 'my-access-secret',
  refreshTokenSecret: 'my-refresh-secret',
  issuer: 'my-app',
  audience: 'api-clients',
  tokenStore: InMemoryTokenStore(),
);
```

RS256 (asymmetric):

```dart
final jwt = JwtService.rs256(
  privateKeyPem: File('private.pem').readAsStringSync(),
  publicKeyPem:  File('public.pem').readAsStringSync(),
  issuer: 'my-app',
  audience: 'api-clients',
);
```

### Generating tokens

```dart
final accessToken = jwt.generateAccessToken(claims: {
  'sub': 'user-123',
  'email': 'alice@example.com',
});

final refreshToken = jwt.generateRefreshToken(accessToken: accessToken);
```

### Protecting routes

```dart
ApiRoute<void, UserProfile>(
  method: ApiMethod.get,
  path: '/me',
  middlewares: [authMiddleware(jwt)],
  security: [SecurityScheme.bearer],      // shows lock icon in Swagger UI
  typedHandler: (req, _) async {
    final user = req.context['user'] as Map<String, dynamic>;
    return getProfile(user['sub'] as String);
  },
)
```

### Token revocation

```dart
await jwt.revokeToken(accessToken);
final payload = await jwt.verifyAccessToken(accessToken); // null
```

### API key middleware

```dart
ApiRoute(
  method: ApiMethod.post,
  path: '/webhooks/stripe',
  middlewares: [apiKeyMiddleware(validKeys: {'whsec_abc123'})],
  typedHandler: handleStripeWebhook,
)
```

---

## Middleware

### Opt-in pipeline helpers (via `DartAPI`)

```dart
app.enableCompression();                                         // gzip responses
app.enableBackgroundTasks();                                     // req.backgroundTasks
app.enableTimeout(const Duration(seconds: 30));                 // 503 on timeout
app.enableRateLimit(maxRequests: 100, window: Duration(minutes: 1));
app.enableMetrics();                                             // GET /metrics
app.enableHealthCheck();                                         // GET /health
app.enableDocs(title: 'My API', version: '1.0.0');             // GET /docs
```

### Per-route middleware

```dart
ApiRoute(
  middlewares: [authMiddleware(jwtService)],
  ...
)
```

### Middleware reference

| Middleware | Description |
|-----------|-------------|
| `loggingMiddleware()` | Logs method, URI, status |
| `globalExceptionMiddleware(onError:)` | Catch-all exception handler |
| `rateLimitMiddleware(maxRequests:, window:)` | Token-bucket rate limiter; returns 429 |
| `requestIdMiddleware()` | Attaches `X-Request-Id`; stores in `context['requestId']` |
| `compressionMiddleware(threshold:)` | Gzip responses above threshold |
| `backgroundTaskMiddleware()` | Enables `request.backgroundTasks` |
| `cacheMiddleware(ttl:, keyExtractor:)` | In-memory GET cache; adds `X-Cache: HIT/MISS` |
| `authMiddleware(jwtService)` | JWT Bearer token validation |
| `apiKeyMiddleware(validKeys:, header:)` | Static API key validation |

---

## Path Parameters

Use `request.pathParam<T>(name)` for typed path parameters, `request.queryParam<T>(name)` for query params, `request.header<T>(name)` for headers.

---

## Pagination

`Pagination.fromRequest()` reads `?page` and `?limit`, clamps them, and computes the SQL offset:

```dart
final p = Pagination.fromRequest(request, defaultLimit: 20, maxLimit: 100);
// p.page, p.limit, p.offset

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

## Response Caching

### Per-route (recommended)

```dart
ApiRoute(
  method: ApiMethod.get,
  path: '/products',
  cacheTtl: Duration(minutes: 10),
  typedHandler: (req, _) async => fetchProducts(),
)
```

### Global

```dart
Pipeline()
  .addMiddleware(cacheMiddleware(ttl: Duration(minutes: 10)))
  .addHandler(router.handler)
```

Cached responses include `X-Cache: HIT`; misses include `X-Cache: MISS`. Only 200 GET responses are cached.

---

## Background Tasks

Schedule async work to run after the response has been sent (similar to FastAPI's `BackgroundTasks`):

```dart
// Enable once:
app.enableBackgroundTasks();

// In a handler:
typedHandler: (req, dto) async {
  final user = await createUser(dto!);
  req.backgroundTasks.add(() => emailService.sendWelcome(user.email));
  return user;  // response sent immediately; email sends after
}
```

Tasks run sequentially after the response resolves. Errors in tasks are swallowed.

---

## OpenAPI / Swagger Docs

```dart
app.addControllers([userController, productController]);
app.enableDocs(
  title: 'My App',
  version: '1.0.0',
  schemas: {'CreateUserDTO': CreateUserDTO.schema},  // optional shared schemas
);
await app.start();
```

| Endpoint | Description |
|----------|-------------|
| `GET /openapi.json` | OpenAPI 3.0 spec |
| `GET /docs` | Swagger UI (with persistent Bearer token support) |
| `GET /redoc` | ReDoc UI |

**Documenting query parameters** — use `QueryParamSpec` so params appear in Swagger UI:

```dart
ApiRoute(
  method: ApiMethod.get,
  path: '/users',
  queryParams: [
    QueryParamSpec('page',   type: 'integer', defaultValue: 1),
    QueryParamSpec('limit',  type: 'integer', defaultValue: 20),
    QueryParamSpec('search', description: 'Filter by name'),
  ],
  typedHandler: ...,
)
```

**Shared schemas with `$ref`** — register named schemas and reference them:

```dart
app.enableDocs(schemas: {'CreateUserDTO': CreateUserDTO.schema});

// on a route:
ApiRoute(requestSchema: {r'$ref': '#/components/schemas/CreateUserDTO'}, ...)
```

---

## Environment Config

```dart
final env = mergeEnv([
  loadEnvFile('env/.env'),
  loadEnvFile('env/.env.dev'),
]);
final config = AppConfig(environment: env);
// config.port, config.jwtAccessSecret, config.corsOrigin, config.dbName, etc.
```

`loadEnvFile` is gracefully ignored when the file doesn't exist.

---

## WebSocket Support

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

---

## Server-Sent Events

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

---

## File Uploads

```dart
Future<String> uploadAvatar(Request request, void _) async {
  if (!request.isMultipart) throw ApiException(400, 'Expected multipart/form-data');
  final avatar = await request.file('avatar');
  if (avatar == null) throw ApiException(400, 'Missing file field "avatar"');
  await saveFile(avatar.filename!, avatar.bytes);
  return 'Uploaded ${avatar.filename}';
}
```

---

## Prometheus Metrics

```dart
app.enableMetrics();   // registers GET /metrics
```

Exposes:
- `http_requests_total{method, path, status}` — request counter
- `http_request_duration_seconds{method, path}` — latency histogram

---

## HTTP Test Client

```dart
import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

void main() {
  late DartApiTestClient client;

  setUp(() {
    final router = RouterManager();
    router.registerController(UserController(...));
    client = DartApiTestClient(router.handler.call);
  });

  test('GET /users returns 200', () async {
    final res = await client.get('/users');
    expect(res.statusCode, 200);
    expect(res.json<List>(), isNotEmpty);
  });
}
```

Pass `defaultHeaders` once to authenticate the whole suite:

```dart
client = DartApiTestClient(
  router.handler.call,
  defaultHeaders: {'authorization': 'Bearer $adminToken'},
);
```

---

## Links

- [dartapi CLI](https://pub.dev/packages/dartapi)
- [dartapi_db](https://pub.dev/packages/dartapi_db)
- [Minimal example](example/minimal/)
- [Full REST API example](example/rest_api/)
- [Standalone starter](example/standalone_no_cli/)
- [GitHub](https://github.com/akashgk/dartapi_core)

---

## License

BSD 3-Clause License © 2025 Akash G Krishnan
