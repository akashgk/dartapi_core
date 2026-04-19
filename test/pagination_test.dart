import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Pagination.fromRequest', () {
    Request req(String query) =>
        Request('GET', Uri.parse('http://localhost/items?$query'));

    test('defaults to page=1 and provided defaultLimit', () {
      final p = Pagination.fromRequest(req(''), defaultLimit: 20);
      expect(p.page, equals(1));
      expect(p.limit, equals(20));
    });

    test('reads page and limit from query params', () {
      final p = Pagination.fromRequest(req('page=3&limit=10'));
      expect(p.page, equals(3));
      expect(p.limit, equals(10));
    });

    test('clamps page to minimum of 1', () {
      final p = Pagination.fromRequest(req('page=0'));
      expect(p.page, equals(1));
    });

    test('clamps limit to maxLimit', () {
      final p = Pagination.fromRequest(req('limit=500'), maxLimit: 100);
      expect(p.limit, equals(100));
    });

    test('computes correct offset', () {
      final p = Pagination.fromRequest(req('page=3&limit=10'));
      expect(p.offset, equals(20));
    });

    test('page=1 gives offset=0', () {
      final p = Pagination.fromRequest(req('page=1&limit=10'));
      expect(p.offset, equals(0));
    });
  });

  group('PaginatedResponse', () {
    test('toJson includes data and meta', () {
      final p = Pagination(page: 2, limit: 10);
      final resp = PaginatedResponse(data: [1, 2, 3], pagination: p, total: 25);
      final json = resp.toJson();

      expect(json['data'], equals([1, 2, 3]));
      expect(json['meta']['page'], equals(2));
      expect(json['meta']['limit'], equals(10));
      expect(json['meta']['total'], equals(25));
      expect(json['meta']['totalPages'], equals(3));
      expect(json['meta']['hasNext'], isTrue);
      expect(json['meta']['hasPrev'], isTrue);
    });

    test('hasPrev is false on first page', () {
      final p = Pagination(page: 1, limit: 10);
      final resp = PaginatedResponse(data: [], pagination: p, total: 50);
      expect(resp.hasPrev, isFalse);
    });

    test('hasNext is false on last page', () {
      final p = Pagination(page: 5, limit: 10);
      final resp = PaginatedResponse(data: [], pagination: p, total: 50);
      expect(resp.hasNext, isFalse);
    });

    test('totalPages is 0 when total is 0', () {
      final p = Pagination(page: 1, limit: 10);
      final resp = PaginatedResponse(data: [], pagination: p, total: 0);
      expect(resp.totalPages, equals(0));
    });

    test('serializes Serializable items via toJson()', () {
      final item = _FakeItem('hello');
      final p = Pagination(page: 1, limit: 10);
      final resp = PaginatedResponse(data: [item], pagination: p, total: 1);
      final json = resp.toJson();
      expect((json['data'] as List).first, equals({'value': 'hello'}));
    });
  });
}

class _FakeItem implements Serializable {
  final String value;
  _FakeItem(this.value);
  @override
  Map<String, dynamic> toJson() => {'value': value};
}
