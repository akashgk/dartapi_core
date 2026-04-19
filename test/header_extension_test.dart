import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('RequestExtensions.header', () {
    Request makeReq({Map<String, String> headers = const {}}) =>
        Request('GET', Uri.parse('http://localhost/'), headers: headers);

    test('returns string header', () {
      final req = makeReq(headers: {'accept-language': 'en-US'});
      expect(req.header<String>('Accept-Language'), equals('en-US'));
    });

    test('is case-insensitive', () {
      final req = makeReq(headers: {'x-api-version': '3'});
      expect(req.header<String>('X-Api-Version'), equals('3'));
    });

    test('returns int header', () {
      final req = makeReq(headers: {'x-api-version': '3'});
      expect(req.header<int>('x-api-version'), equals(3));
    });

    test('returns double header', () {
      final req = makeReq(headers: {'x-score': '9.5'});
      expect(req.header<double>('x-score'), equals(9.5));
    });

    test('returns bool header', () {
      final req = makeReq(headers: {'x-debug': 'true'});
      expect(req.header<bool>('x-debug'), isTrue);
    });

    test('returns defaultValue when header is absent', () {
      final req = makeReq();
      expect(req.header<int>('x-api-version', defaultValue: 1), equals(1));
    });

    test('returns null when header is absent and no default', () {
      final req = makeReq();
      expect(req.header<String>('x-custom'), isNull);
    });

    test('throws ApiException 400 on bad int value', () {
      final req = makeReq(headers: {'x-count': 'abc'});
      expect(() => req.header<int>('x-count'), throwsA(isA<ApiException>()));
    });
  });
}
