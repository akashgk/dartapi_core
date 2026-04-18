import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('RequestExtensions - pathParam', () {
    Request makeRequestWithParams(Map<String, String> params) {
      return Request(
        'GET',
        Uri.parse('http://localhost/test'),
        context: {'shelf_router/params': params},
      );
    }

    test('extracts String path param', () {
      final req = makeRequestWithParams({'slug': 'hello'});
      expect(req.pathParam<String>('slug'), equals('hello'));
    });

    test('extracts int path param', () {
      final req = makeRequestWithParams({'id': '42'});
      expect(req.pathParam<int>('id'), equals(42));
    });

    test('extracts double path param', () {
      final req = makeRequestWithParams({'price': '9.99'});
      expect(req.pathParam<double>('price'), equals(9.99));
    });

    test('extracts bool path param', () {
      final req = makeRequestWithParams({'active': 'true'});
      expect(req.pathParam<bool>('active'), isTrue);
    });

    test('throws ApiException 400 when path param is missing', () {
      final req = makeRequestWithParams({});
      expect(
        () => req.pathParam<int>('id'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('"id"')),
        ),
      );
    });

    test('throws ApiException 400 when int param is not a number', () {
      final req = makeRequestWithParams({'id': 'abc'});
      expect(
        () => req.pathParam<int>('id'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('throws ApiException 400 when double param is not a number', () {
      final req = makeRequestWithParams({'price': 'cheap'});
      expect(
        () => req.pathParam<double>('price'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('RequestExtensions - queryParam', () {
    Request makeRequestWithQuery(Map<String, String> params) {
      final uri = Uri(
        scheme: 'http',
        host: 'localhost',
        path: '/test',
        queryParameters: params,
      );
      return Request('GET', uri);
    }

    test('extracts String query param', () {
      final req = makeRequestWithQuery({'q': 'dart'});
      expect(req.queryParam<String>('q'), equals('dart'));
    });

    test('extracts int query param', () {
      final req = makeRequestWithQuery({'page': '3'});
      expect(req.queryParam<int>('page'), equals(3));
    });

    test('returns defaultValue when param is absent', () {
      final req = makeRequestWithQuery({});
      expect(req.queryParam<int>('page', defaultValue: 1), equals(1));
    });

    test('returns null when param is absent and no default', () {
      final req = makeRequestWithQuery({});
      expect(req.queryParam<String>('q'), isNull);
    });

    test('throws ApiException 400 when int query param is not a number', () {
      final req = makeRequestWithQuery({'page': 'first'});
      expect(
        () => req.queryParam<int>('page'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
