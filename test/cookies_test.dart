import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('CookieRequestExtensions', () {
    Request makeReq({String cookieHeader = ''}) => Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: cookieHeader.isNotEmpty ? {'cookie': cookieHeader} : {},
        );

    test('parses single cookie', () {
      final req = makeReq(cookieHeader: 'session=abc123');
      expect(req.cookies, equals({'session': 'abc123'}));
    });

    test('parses multiple cookies', () {
      final req = makeReq(cookieHeader: 'a=1; b=2; c=3');
      expect(req.cookies, equals({'a': '1', 'b': '2', 'c': '3'}));
    });

    test('returns empty map when no Cookie header', () {
      expect(makeReq().cookies, isEmpty);
    });

    test('cookie() returns value by name', () {
      final req = makeReq(cookieHeader: 'token=xyz');
      expect(req.cookie('token'), equals('xyz'));
    });

    test('cookie() returns null for absent name', () {
      expect(makeReq().cookie('missing'), isNull);
    });
  });

  group('setCookie', () {
    final base = Response.ok('ok');

    test('sets basic cookie', () {
      final res = setCookie(base, 'session', 'abc');
      expect(res.headers['set-cookie'], contains('session=abc'));
    });

    test('includes Max-Age', () {
      final res = setCookie(base, 'x', 'y', maxAge: Duration(hours: 1));
      expect(res.headers['set-cookie'], contains('Max-Age=3600'));
    });

    test('includes Path', () {
      final res = setCookie(base, 'x', 'y', path: '/api');
      expect(res.headers['set-cookie'], contains('Path=/api'));
    });

    test('includes HttpOnly flag', () {
      final res = setCookie(base, 'x', 'y', httpOnly: true);
      expect(res.headers['set-cookie'], contains('HttpOnly'));
    });

    test('includes Secure flag', () {
      final res = setCookie(base, 'x', 'y', secure: true);
      expect(res.headers['set-cookie'], contains('Secure'));
    });

    test('includes SameSite', () {
      final res = setCookie(base, 'x', 'y', sameSite: 'Strict');
      expect(res.headers['set-cookie'], contains('SameSite=Strict'));
    });
  });
}
