# dartapi_core

Core utilities for building typed, structured REST APIs in Dart — routing, validation, middleware, and more.

Part of the [DartAPI](https://pub.dev/packages/dartapi) ecosystem.

---

## Installation

```yaml
dependencies:
  dartapi_core: ^0.0.7
```

---

## Routing

Define endpoints with `ApiRoute<Input, Output>`. The handler is fully typed — the framework handles request parsing, response serialization, and error mapping automatically.

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
      statusCode: 201,              // custom success status code
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
ApiRoute(method: ApiMethod.post,   path: '/users',    statusCode: 201, ...)
ApiRoute(method: ApiMethod.delete, path: '/users/<id>', statusCode: 204, ...)
```

---

## Request Validation

Use `verifyKey<T>()` on request body maps to extract fields with type checking and optional validators:

```dart
factory UserDTO.fromJson(Map<String, dynamic> json) {
  return UserDTO(
    name: json.verifyKey<String>('name'),
    age:  json.verifyKey<int>('age'),
    email: json.verifyKey<String>('email', validators: [
      EmailValidator('Invalid email'),
    ]),
  );
}
```

Throws `ApiException(422)` on missing fields, wrong types, or failed validation.

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

## Middleware

### Logging (built-in)

```dart
Pipeline().addMiddleware(loggingMiddleware())
```

Logs method, URI, and response status for every request.

### Global exception handler

Catch any unhandled exception app-wide and return a controlled error response:

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

---

## Error handling

Throw `ApiException(statusCode, message)` from any handler or validator to return a specific HTTP error:

```dart
throw ApiException(404, 'User not found');
throw ApiException(422, 'Invalid input');
```

The framework catches these automatically and returns the correct JSON response.

---

## Links

- [dartapi CLI](https://pub.dev/packages/dartapi)
- [dartapi_auth](https://pub.dev/packages/dartapi_auth)
- [dartapi_db](https://pub.dev/packages/dartapi_db)
- [GitHub](https://github.com/akashgk/dartapi_core)
