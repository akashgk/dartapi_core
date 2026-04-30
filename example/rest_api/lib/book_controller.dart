import 'package:dartapi_core/dartapi_core.dart';
import 'dtos.dart';
import 'models.dart';
import 'repository.dart';

class BookController extends BaseController {
  final BookRepository _repo;
  final JwtService _jwt;

  BookController({required BookRepository repo, required JwtService jwt})
      : _repo = repo,
        _jwt = jwt;

  @override
  List<ApiRoute> get routes => [
        ApiRoute<void, PaginatedResponse>(
          method: ApiMethod.get,
          path: '/books',
          summary: 'List books',
          description: 'Paginated public list.',
          queryParams: [
            QueryParamSpec('page', type: 'integer', defaultValue: 1, description: 'Page number'),
            QueryParamSpec('limit', type: 'integer', defaultValue: 20, description: 'Items per page'),
          ],
          responseSchema: {
            'type': 'object',
            'properties': {
              'data': {'type': 'array'},
              'meta': {'type': 'object'},
            },
          },
          typedHandler: (req, _) async {
            final p = Pagination.fromRequest(req, defaultLimit: 20, maxLimit: 100);
            return PaginatedResponse(
              data: _repo.getAll(page: p.page, limit: p.limit),
              pagination: p,
              total: _repo.total,
            );
          },
        ),

        ApiRoute<void, Book>(
          method: ApiMethod.get,
          path: '/books/<id>',
          summary: 'Get book',
          responseSchema: {r'$ref': '#/components/schemas/Book'},
          typedHandler: (req, _) async {
            final id = req.pathParam<int>('id');
            return _repo.getById(id) ?? (throw const ApiException(404, 'Book not found'));
          },
        ),

        ApiRoute<BookDTO, Book>(
          method: ApiMethod.post,
          path: '/books',
          statusCode: 201,
          summary: 'Create book',
          dtoParser: BookDTO.fromJson,
          requestSchema: {r'$ref': '#/components/schemas/BookDTO'},
          responseSchema: {r'$ref': '#/components/schemas/Book'},
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, dto) async => _repo.create(dto!),
        ),

        ApiRoute<BookDTO, Book>(
          method: ApiMethod.put,
          path: '/books/<id>',
          summary: 'Update book',
          dtoParser: BookDTO.fromJson,
          requestSchema: {r'$ref': '#/components/schemas/BookDTO'},
          responseSchema: {r'$ref': '#/components/schemas/Book'},
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, dto) async {
            final id = req.pathParam<int>('id');
            return _repo.update(id, dto!) ?? (throw const ApiException(404, 'Book not found'));
          },
        ),

        ApiRoute<void, void>(
          method: ApiMethod.delete,
          path: '/books/<id>',
          statusCode: 204,
          summary: 'Delete book',
          middlewares: [authMiddleware(_jwt)],
          security: [SecurityScheme.bearer],
          typedHandler: (req, _) async {
            final id = req.pathParam<int>('id');
            if (!_repo.delete(id)) throw const ApiException(404, 'Book not found');
          },
        ),
      ];
}
