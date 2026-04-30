# minimal

The smallest possible dartapi_core server — one file, one route, Swagger UI included.

## Run

```bash
dart pub get
dart run bin/main.dart
```

Open [http://localhost:8080/docs](http://localhost:8080/docs) for Swagger UI.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/hello` | Returns a greeting |
| GET | `/health` | Health check |
| GET | `/docs` | Swagger UI |
| GET | `/openapi.json` | Raw OpenAPI spec |
