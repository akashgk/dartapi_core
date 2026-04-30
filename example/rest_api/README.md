# rest_api

Full CRUD Books API demonstrating the core dartapi_core features:

- **`FieldSet` DTOs** — declare fields once, get validation + OpenAPI schema from same source
- **JWT auth** — `JwtService` + `authMiddleware` on mutating routes
- **ServiceRegistry** — lazy singleton dependency injection
- **QueryParamSpec** — query params documented in Swagger UI
- **`$ref` schemas** — shared `components/schemas` in OpenAPI spec
- **DartApiTestClient** — in-process tests with zero network overhead

## Run

```bash
dart pub get
dart run bin/main.dart
```

Open [http://localhost:8080/docs](http://localhost:8080/docs) for Swagger UI.

Login: `POST /auth/login` with `{"email":"demo@example.com","password":"demo1234"}` to get a Bearer token.

## Test

```bash
dart test
```

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/login` | — | Get access token |
| GET | `/books` | — | Paginated list (`?page=1&limit=20`) |
| GET | `/books/:id` | — | Get by ID |
| POST | `/books` | Bearer | Create |
| PUT | `/books/:id` | Bearer | Update |
| DELETE | `/books/:id` | Bearer | Delete |
