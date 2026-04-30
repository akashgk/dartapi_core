// ignore_for_file: avoid_print
import 'dart:io';
import 'package:dartapi_core/dartapi_core.dart';
import 'package:rest_api/book_controller.dart';
import 'package:rest_api/dtos.dart';
import 'package:rest_api/repository.dart';

void main() async {
  final app = DartAPI(appName: 'rest-api');

  app.register<BookRepository>((_) => BookRepository());

  final secret = Platform.environment['JWT_SECRET'] ?? 'dev-secret-change-me';
  app.register<JwtService>(
    (_) => JwtService(
      accessTokenSecret: secret,
      refreshTokenSecret: '$secret-refresh',
      issuer: 'rest-api',
      audience: 'rest-api-users',
    ),
  );

  final jwt = app.get<JwtService>();

  app.addControllers([
    InlineController([
      ApiRoute<Map<String, dynamic>, Map<String, String>>(
        method: ApiMethod.post,
        path: '/auth/login',
        summary: 'Login',
        description: 'Returns an access token.\n\nDemo: `{"email":"demo@example.com","password":"demo1234"}`',
        dtoParser: (json) => json,
        requestSchema: {
          'type': 'object',
          'required': ['email', 'password'],
          'properties': {
            'email': {'type': 'string', 'format': 'email'},
            'password': {'type': 'string'},
          },
        },
        typedHandler: (req, body) async {
          final email = body?['email'];
          final password = body?['password'];
          if (email != 'demo@example.com' || password != 'demo1234') {
            throw const ApiException(401, 'Invalid credentials');
          }
          return {
            'accessToken': jwt.generateAccessToken(claims: {'sub': '1', 'email': email}),
          };
        },
      ),
    ]),
    BookController(repo: app.get<BookRepository>(), jwt: jwt),
  ]);

  app.enableHealthCheck();
  app.enableDocs(
    title: 'Books REST API',
    version: '1.0.0',
    schemas: {
      'Book': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
          'title': {'type': 'string'},
          'author': {'type': 'string'},
          'year': {'type': 'integer'},
        },
      },
      'BookDTO': BookDTO.schema,
    },
    tagDescriptions: {
      'Books': 'CRUD operations for the book catalogue',
    },
  );

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  print('Books REST API  →  http://localhost:$port');
  print('  Swagger UI:  http://localhost:$port/docs');
  print('  Login:       POST /auth/login  {"email":"demo@example.com","password":"demo1234"}');

  await app.start(port: port);
}
