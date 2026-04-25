/// A self-contained Books API showcasing the core features of dartapi_core:
///
///   ● [DartAPI] server with middleware pipeline
///   ● [ServiceRegistry] for dependency injection
///   ● JWT auth ([JwtService], [authMiddleware], [InMemoryTokenStore])
///   ● [BaseController] with typed [ApiRoute]s, DTO validation, and caching
///   ● [Pagination] and [PaginatedResponse]
///   ● Background tasks (post-response async work)
///   ● [InlineController] for one-off routes
///   ● [AppConfig] / [loadEnvFile] for environment config
///   ● [ApiException] for typed HTTP errors
///   ● Health check, Prometheus metrics, OpenAPI docs
///
/// Run:
///   dart example/dartapi_core_example.dart
///
/// Open:
///   http://localhost:8080/docs     — Swagger UI
///   http://localhost:8080/health   — health check
///   http://localhost:8080/books    — public book list
///
/// Login (returns JWT):
///   POST /auth/login  {"email":"demo@example.com","password":"demo1234"}
// ignore_for_file: avoid_print
library;

import 'dart:io';
import 'package:dartapi_core/dartapi_core.dart';

// ── Domain model ──────────────────────────────────────────────────────────────

class Book implements Serializable {
  final int id;
  final String title;
  final String author;
  final int year;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.year,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'year': year,
      };

  static const schema = {
    'type': 'object',
    'properties': {
      'id': {'type': 'integer'},
      'title': {'type': 'string'},
      'author': {'type': 'string'},
      'year': {'type': 'integer'},
    },
  };
}

// ── DTO with validation ───────────────────────────────────────────────────────

class BookDTO {
  final String title;
  final String author;
  final int year;

  const BookDTO({
    required this.title,
    required this.author,
    required this.year,
  });

  /// Parses and validates the request body.
  ///
  /// Throws [ApiException(422)] with all field errors collected before throwing
  /// (no short-circuit — the caller sees every invalid field at once).
  factory BookDTO.fromJson(Map<String, dynamic> json) {
    json.validateAll({
      'title': () => json.verifyKey<String>(
            'title',
            validators: [NotEmptyValidator(), MaxLengthValidator(200)],
          ),
      'author': () => json.verifyKey<String>(
            'author',
            validators: [NotEmptyValidator()],
          ),
      'year': () => json.verifyKey<int>('year'),
    });

    return BookDTO(
      title: json['title'] as String,
      author: json['author'] as String,
      year: json['year'] as int,
    );
  }

  static const schema = {
    'type': 'object',
    'required': ['title', 'author', 'year'],
    'properties': {
      'title': {'type': 'string', 'maxLength': 200, 'example': 'Clean Code'},
      'author': {'type': 'string', 'example': 'Robert C. Martin'},
      'year': {'type': 'integer', 'example': 2008},
    },
  };
}

// ── Repository (in-memory) ────────────────────────────────────────────────────

class BookRepository {
  final List<Book> _books = [
    const Book(id: 1, title: 'Clean Code', author: 'Robert C. Martin', year: 2008),
    const Book(id: 2, title: 'The Pragmatic Programmer', author: 'David Thomas', year: 1999),
    const Book(id: 3, title: 'Design Patterns', author: 'GoF', year: 1994),
    const Book(id: 4, title: 'Refactoring', author: 'Martin Fowler', year: 1999),
    const Book(id: 5, title: 'Domain-Driven Design', author: 'Eric Evans', year: 2003),
  ];
  int _nextId = 6;

  List<Book> getAll({required int page, required int limit}) {
    final offset = (page - 1) * limit;
    return _books.skip(offset).take(limit).toList();
  }

  int get total => _books.length;

  Book? getById(int id) => _books.where((b) => b.id == id).firstOrNull;

  Book create(BookDTO dto) {
    final book = Book(
      id: _nextId++,
      title: dto.title,
      author: dto.author,
      year: dto.year,
    );
    _books.add(book);
    return book;
  }

  Book? update(int id, BookDTO dto) {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx == -1) return null;
    final updated = Book(id: id, title: dto.title, author: dto.author, year: dto.year);
    _books[idx] = updated;
    return updated;
  }

  bool delete(int id) {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx == -1) return false;
    _books.removeAt(idx);
    return true;
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class BookService {
  final BookRepository _repo;
  BookService(this._repo);

  ({List<Book> books, int total}) list({required int page, required int limit}) =>
      (books: _repo.getAll(page: page, limit: limit), total: _repo.total);

  Book get(int id) =>
      _repo.getById(id) ?? (throw const ApiException(404, 'Book not found'));

  Book create(BookDTO dto) => _repo.create(dto);

  Book update(int id, BookDTO dto) =>
      _repo.update(id, dto) ?? (throw const ApiException(404, 'Book not found'));

  void delete(int id) {
    if (!_repo.delete(id)) throw const ApiException(404, 'Book not found');
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

class BookController extends BaseController {
  final BookService _service;
  final JwtService _jwt;

  BookController({required BookService service, required JwtService jwt})
      : _service = service,
        _jwt = jwt;

  @override
  List<ApiRoute> get routes => [
        // ── GET /books — public, paginated, cached ───────────────────────────
        ApiRoute<void, PaginatedResponse>(
          method: ApiMethod.get,
          path: '/books',
          summary: 'List books',
          description: 'Public paginated list. Supports `?page` and `?limit` (max 50). '
              'Response cached for 30 seconds.',
          cacheTtl: const Duration(seconds: 30),
          responseSchema: {
            'type': 'object',
            'properties': {
              'data': {'type': 'array', 'items': Book.schema},
              'meta': {
                'type': 'object',
                'properties': {
                  'page': {'type': 'integer'},
                  'limit': {'type': 'integer'},
                  'total': {'type': 'integer'},
                  'totalPages': {'type': 'integer'},
                  'hasNext': {'type': 'boolean'},
                  'hasPrev': {'type': 'boolean'},
                },
              },
            },
          },
          typedHandler: (req, _) async {
            final p = Pagination.fromRequest(req, defaultLimit: 3, maxLimit: 50);
            final (:books, :total) = _service.list(page: p.page, limit: p.limit);
            return PaginatedResponse(data: books, pagination: p, total: total);
          },
        ),

        // ── GET /books/:id — requires auth ───────────────────────────────────
        ApiRoute<void, Book>(
          method: ApiMethod.get,
          path: '/books/<id>',
          summary: 'Get book',
          description: 'Returns a single book by ID. Requires a valid Bearer token.',
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          responseSchema: Book.schema,
          typedHandler: (req, _) async => _service.get(req.pathParam<int>('id')),
        ),

        // ── POST /books — requires auth, fires background task ───────────────
        ApiRoute<BookDTO, Book>(
          method: ApiMethod.post,
          path: '/books',
          statusCode: 201,
          summary: 'Create book',
          description: 'Creates a new book. Requires auth. '
              'A background task fires after the response is sent '
              '(simulates an audit log entry).',
          dtoParser: BookDTO.fromJson,
          requestSchema: BookDTO.schema,
          responseSchema: Book.schema,
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, dto) async {
            final book = _service.create(dto!);
            req.backgroundTasks.add(() async {
              // Runs after the 201 response is delivered to the client.
              print('[audit] Book created: id=${book.id} "${book.title}"');
            });
            return book;
          },
        ),

        // ── PUT /books/:id — requires auth ───────────────────────────────────
        ApiRoute<BookDTO, Book>(
          method: ApiMethod.put,
          path: '/books/<id>',
          summary: 'Update book',
          description: 'Replaces all fields of an existing book.',
          dtoParser: BookDTO.fromJson,
          requestSchema: BookDTO.schema,
          responseSchema: Book.schema,
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, dto) async =>
              _service.update(req.pathParam<int>('id'), dto!),
        ),

        // ── DELETE /books/:id — requires auth ────────────────────────────────
        ApiRoute<void, void>(
          method: ApiMethod.delete,
          path: '/books/<id>',
          statusCode: 204,
          summary: 'Delete book',
          description: 'Permanently removes a book. Returns 204 on success.',
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, _) async => _service.delete(req.pathParam<int>('id')),
        ),
      ];
}

// ── Minimal hardcoded user store (replace with a real DB in production) ───────

const _demoCredentials = {
  'email': 'demo@example.com',
  'password': 'demo1234',
};

Map<String, dynamic>? _authenticate(String email, String password) {
  if (email == _demoCredentials['email'] && password == _demoCredentials['password']) {
    return {'sub': '1', 'email': email, 'role': 'user'};
  }
  return null;
}

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main() async {
  // Load .env files — gracefully ignored when files don't exist.
  final env = mergeEnv([
    loadEnvFile('env/.env'),
    loadEnvFile('env/.env.dev'),
  ]);
  final config = AppConfig(environment: env);

  final app = DartAPI(appName: 'books-api', corsOrigin: config.corsOrigin);

  // ── Dependency injection via ServiceRegistry ──────────────────────────────
  //
  // Registrations are lazy singletons — constructed on the first get<T>() call.
  // The factory receives the registry so it can resolve sub-dependencies.

  app.register<BookRepository>((_) => BookRepository());

  app.register<BookService>(
    (r) => BookService(r.get<BookRepository>()),
  );

  app.register<InMemoryTokenStore>((_) => InMemoryTokenStore());

  app.register<JwtService>(
    (r) => JwtService(
      accessTokenSecret: config.jwtAccessSecret,
      refreshTokenSecret: config.jwtRefreshSecret,
      issuer: 'books-api',
      audience: 'books-api-users',
      tokenStore: r.get<InMemoryTokenStore>(),
    ),
  );

  // ── Middleware pipeline ───────────────────────────────────────────────────
  app.enableCompression();
  app.enableBackgroundTasks();
  app.enableTimeout(const Duration(seconds: 30));
  app.enableRateLimit(maxRequests: 100, window: const Duration(minutes: 1));

  // ── Auth routes (inline — no dedicated controller needed) ─────────────────
  final jwt = app.get<JwtService>();

  app.addControllers([
    InlineController([
      // POST /auth/login — returns access + refresh tokens
      ApiRoute<Map<String, dynamic>, Map<String, String>>(
        method: ApiMethod.post,
        path: '/auth/login',
        summary: 'Login',
        description: 'Returns an access + refresh token pair.\n\n'
            'Demo credentials: `demo@example.com` / `demo1234`',
        dtoParser: (json) => json,
        requestSchema: {
          'type': 'object',
          'required': ['email', 'password'],
          'properties': {
            'email': {'type': 'string', 'format': 'email', 'example': 'demo@example.com'},
            'password': {'type': 'string', 'example': 'demo1234'},
          },
        },
        typedHandler: (req, body) async {
          final email = body?['email']?.toString() ?? '';
          final password = body?['password']?.toString() ?? '';
          final claims = _authenticate(email, password);
          if (claims == null) throw const ApiException(401, 'Invalid credentials');
          final accessToken = jwt.generateAccessToken(claims: claims);
          return {
            'accessToken': accessToken,
            'refreshToken': jwt.generateRefreshToken(accessToken: accessToken),
          };
        },
      ),

      // POST /auth/refresh — exchange refresh token for new access token
      ApiRoute<Map<String, dynamic>, Map<String, String>>(
        method: ApiMethod.post,
        path: '/auth/refresh',
        summary: 'Refresh token',
        description: 'Exchange a valid refresh token for a new access token.',
        dtoParser: (json) => json,
        requestSchema: {
          'type': 'object',
          'required': ['refreshToken'],
          'properties': {
            'refreshToken': {'type': 'string'},
          },
        },
        typedHandler: (req, body) async {
          final token = body?['refreshToken']?.toString();
          if (token == null) throw const ApiException(400, 'refreshToken is required');
          final claims = await jwt.verifyRefreshToken(token);
          if (claims == null) throw const ApiException(401, 'Invalid or expired refresh token');
          final newAccess = jwt.generateAccessToken(claims: {
            'sub': claims['sub'],
            'email': claims['email'] ?? '',
          });
          return {'accessToken': newAccess};
        },
      ),

      // POST /auth/logout — revokes the current access token
      ApiRoute<void, Map<String, String>>(
        method: ApiMethod.post,
        path: '/auth/logout',
        summary: 'Logout',
        description: 'Revokes the Bearer token from the Authorization header.',
        middlewares: [authMiddleware(jwt)],
        security: [SecurityScheme.bearer],
        typedHandler: (req, _) async {
          final token = req.headers.getToken();
          if (token != null) await jwt.revokeToken(token);
          return {'message': 'Logged out'};
        },
      ),
    ]),

    // ── Book CRUD ─────────────────────────────────────────────────────────
    BookController(
      service: app.get<BookService>(),
      jwt: jwt,
    ),
  ]);

  // ── Built-in endpoints ────────────────────────────────────────────────────
  app.enableHealthCheck();                                // GET /health
  app.enableMetrics();                                    // GET /metrics (Prometheus)
  app.enableDocs(title: 'Books API', version: '1.0.0');  // GET /docs (Swagger UI)

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  print('');
  print('Books API  →  http://localhost:$port');
  print('─' * 44);
  print('  Swagger UI  http://localhost:$port/docs');
  print('  Health      http://localhost:$port/health');
  print('  Metrics     http://localhost:$port/metrics');
  print('─' * 44);
  print('  Public:  GET  /books');
  print('  Auth:    POST /auth/login');
  print('           POST /auth/refresh');
  print('           POST /auth/logout  (Bearer)');
  print('  Books:   GET  /books/:id    (Bearer)');
  print('           POST /books        (Bearer)');
  print('           PUT  /books/:id    (Bearer)');
  print('           DELETE /books/:id  (Bearer)');
  print('─' * 44);
  print('  Demo login: demo@example.com / demo1234');
  print('');

  await app.start(port: port);
}
