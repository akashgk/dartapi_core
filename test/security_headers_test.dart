import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('securityHeadersMiddleware', () {
    Response ok(Request _) => Response.ok('ok');
    final req = Request('GET', Uri.parse('http://localhost/'));

    Handler withDefaults() => Pipeline()
        .addMiddleware(securityHeadersMiddleware())
        .addHandler(ok);

    test('adds X-Frame-Options: DENY', () async {
      final res = await withDefaults()(req);
      expect(res.headers['x-frame-options'], equals('DENY'));
    });

    test('adds X-Content-Type-Options: nosniff', () async {
      final res = await withDefaults()(req);
      expect(res.headers['x-content-type-options'], equals('nosniff'));
    });

    test('adds Referrer-Policy', () async {
      final res = await withDefaults()(req);
      expect(
        res.headers['referrer-policy'],
        equals('strict-origin-when-cross-origin'),
      );
    });

    test('adds X-XSS-Protection', () async {
      final res = await withDefaults()(req);
      expect(res.headers['x-xss-protection'], equals('1; mode=block'));
    });

    test('adds Permissions-Policy', () async {
      final res = await withDefaults()(req);
      expect(
        res.headers['permissions-policy'],
        equals('camera=(), microphone=(), geolocation=()'),
      );
    });

    test('does not add CSP by default', () async {
      final res = await withDefaults()(req);
      expect(res.headers['content-security-policy'], isNull);
    });

    test('adds CSP when provided', () async {
      final handler = Pipeline()
          .addMiddleware(
            securityHeadersMiddleware(
              contentSecurityPolicy: "default-src 'self'",
            ),
          )
          .addHandler(ok);
      final res = await handler(req);
      expect(res.headers['content-security-policy'], equals("default-src 'self'"));
    });

    test('adds HSTS when provided', () async {
      final handler = Pipeline()
          .addMiddleware(
            securityHeadersMiddleware(
              strictTransportSecurity:
                  'max-age=31536000; includeSubDomains',
            ),
          )
          .addHandler(ok);
      final res = await handler(req);
      expect(
        res.headers['strict-transport-security'],
        equals('max-age=31536000; includeSubDomains'),
      );
    });

    test('custom values override defaults', () async {
      final handler = Pipeline()
          .addMiddleware(
            securityHeadersMiddleware(xFrameOptions: 'SAMEORIGIN'),
          )
          .addHandler(ok);
      final res = await handler(req);
      expect(res.headers['x-frame-options'], equals('SAMEORIGIN'));
    });

    test('does not remove existing response headers', () async {
      final handler = Pipeline()
          .addMiddleware(securityHeadersMiddleware())
          .addHandler((_) => Response.ok('ok', headers: {'X-Custom': 'value'}));
      final res = await handler(req);
      expect(res.headers['x-custom'], equals('value'));
    });
  });
}
