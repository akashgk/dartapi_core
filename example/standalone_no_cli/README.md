# standalone_no_cli

A minimal dartapi_core project written by hand — equivalent to what `dartapi create --minimal` generates. Use this as a reference when starting without the CLI.

## File structure

```
bin/
  main.dart          ← entry point: DartAPI setup, middleware, controllers, start
lib/
  hello_controller.dart  ← a BaseController with two GET routes
pubspec.yaml         ← only dartapi_core as a dependency
```

## Why each file exists

**`bin/main.dart`** — The server entry point. Creates a `DartAPI` instance, registers
optional middleware (compression, health check), adds controllers, enables Swagger UI
docs, then starts the HTTP server. This is the only place that knows about ports and
server lifecycle.

**`lib/hello_controller.dart`** — Groups related routes under a `BaseController`
subclass. Implements `get routes` and returns a `List<ApiRoute>`. Each `ApiRoute`
declares the HTTP method, path, and a typed handler. Keep controllers focused on a
single resource or feature.

**How to add a route** — Add another `ApiRoute` to `HelloController.routes`, or create
a new controller class and pass it to `app.addControllers([...])`.

**How to add auth** — Register a `JwtService` with `app.register<JwtService>(...)`,
then add `middlewares: [authMiddleware(jwt)]` to any route that requires a token.

## Run

```bash
dart pub get
dart run bin/main.dart
```

Open [http://localhost:8080/docs](http://localhost:8080/docs) for Swagger UI.

| Method | Path | Description |
|---|---|---|
| GET | `/hello` | Returns a greeting |
| GET | `/hello/:name` | Greet by name |
| GET | `/health` | Health check |
| GET | `/docs` | Swagger UI |
