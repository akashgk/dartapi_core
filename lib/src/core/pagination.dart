import 'package:shelf/shelf.dart';
import '../utils/extensions.dart';
import 'serializable.dart';

/// Extracts `page` and `limit` query parameters from a request and computes `offset`.
///
/// ```dart
/// final p = Pagination.fromRequest(request);
/// final rows = await db.select('products', limit: p.limit, offset: p.offset);
/// return PaginatedResponse(data: rows, pagination: p, total: total);
/// ```
class Pagination {
  final int page;
  final int limit;

  const Pagination({required this.page, required this.limit});

  /// Reads `?page` and `?limit` from [request].
  ///
  /// [page] is clamped to a minimum of 1.
  /// [limit] is clamped to `[1, maxLimit]` (default max: 100).
  factory Pagination.fromRequest(
    Request request, {
    int defaultLimit = 20,
    int maxLimit = 100,
  }) {
    final page =
        (request.queryParam<int>('page', defaultValue: 1) ?? 1).clamp(1, 1 << 30);
    final limit =
        (request.queryParam<int>('limit', defaultValue: defaultLimit) ?? defaultLimit)
            .clamp(1, maxLimit);
    return Pagination(page: page, limit: limit);
  }

  /// Zero-based offset suitable for SQL `LIMIT`/`OFFSET` queries.
  int get offset => (page - 1) * limit;
}

/// A generic paginated response wrapper that implements [Serializable].
///
/// ```dart
/// return PaginatedResponse(
///   data: products,
///   pagination: p,
///   total: totalCount,
/// );
/// ```
///
/// Serializes to:
/// ```json
/// {
///   "data": [...],
///   "meta": { "page": 1, "limit": 20, "total": 100, "totalPages": 5, "hasNext": true, "hasPrev": false }
/// }
/// ```
class PaginatedResponse implements Serializable {
  final List<dynamic> data;
  final Pagination pagination;
  final int total;

  const PaginatedResponse({
    required this.data,
    required this.pagination,
    required this.total,
  });

  int get totalPages => total == 0 ? 0 : (total / pagination.limit).ceil();
  bool get hasNext => pagination.page * pagination.limit < total;
  bool get hasPrev => pagination.page > 1;

  @override
  Map<String, dynamic> toJson() => {
        'data': data
            .map((item) => item is Serializable ? item.toJson() : item)
            .toList(),
        'meta': {
          'page': pagination.page,
          'limit': pagination.limit,
          'total': total,
          'totalPages': totalPages,
          'hasNext': hasNext,
          'hasPrev': hasPrev,
        },
      };
}
