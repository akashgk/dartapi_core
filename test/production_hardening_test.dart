import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

/// Self-signed localhost certificate used only by the TLS test below.
const _testCertPem = '''
-----BEGIN CERTIFICATE-----
MIIDCzCCAfOgAwIBAgIUb3AHktMXpDpDT7wqItdsJLs1vl4wDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDcwMjE5MDExNVoYDzIxMjYw
NjA4MTkwMTE1WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQDerO30oBW+l+f5awFYL+qo/7zo2w8NNdZYrCVokEuv
9d0SnKhgQQ3VmN++l1mDRfmeVXGnToavyMQr43UekIn34jTV4Y1/1NMH4tln0KML
NXGnBvlvmRyKhmNXQsuAcmptmkRSlUer7Fsx2mtgbjMPErkDepjyDiWKVQ32Hh0E
KFMH/F8UMhnAHU4ty5lqx7i8mbD0jNwYmNU0l++K6YN5sfN2xRSoyuROZl03pcoB
bVhwGSdKe28EaQ3K5WKZ7+ZzjqUt4HJV/Z3kG/ZMmfSIbVGWuXo4Sze3dB7Z2En8
lucH6LLlkoPdEtNg2m+JPorFeetOWlsxR/+WS1Gg1Yn9AgMBAAGjUzBRMB0GA1Ud
DgQWBBSHEcy59UqiNfp/D/M6zb0H6ttR3TAfBgNVHSMEGDAWgBSHEcy59UqiNfp/
D/M6zb0H6ttR3TAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQB8
zbSJrla+uOzQZkQjKyzxUISU7hypP5YMSMjB/iDV5KlTpeHQEqxcWqKAYqzyqm5j
TEa7w/UsZHbIUxPOFn9M69CnHTc8ongZ0fAfTbwIrattQ1ZY0atFHkQwFs0jisuT
Svz5r+cYkcYI1WW3fOMw/nxBDkY1YXHjK5iHk35SVB3pBewcsXwvhccU8O7oYuwf
PWXr/wQ+vXi0thX9cUGPYofMk+cTYPTFQjkD5oH3dLRwtlOOKT92rQKrRocq78hN
Kc7IHJa8bydiX8XokQ552Y+WM5MGZuIsxxmIPcSNVmYbDgfhoDFpjqwKfEwZBsYR
9GYKzjTA8ZZ+11MWUFbC
-----END CERTIFICATE-----
''';

const _testKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDerO30oBW+l+f5
awFYL+qo/7zo2w8NNdZYrCVokEuv9d0SnKhgQQ3VmN++l1mDRfmeVXGnToavyMQr
43UekIn34jTV4Y1/1NMH4tln0KMLNXGnBvlvmRyKhmNXQsuAcmptmkRSlUer7Fsx
2mtgbjMPErkDepjyDiWKVQ32Hh0EKFMH/F8UMhnAHU4ty5lqx7i8mbD0jNwYmNU0
l++K6YN5sfN2xRSoyuROZl03pcoBbVhwGSdKe28EaQ3K5WKZ7+ZzjqUt4HJV/Z3k
G/ZMmfSIbVGWuXo4Sze3dB7Z2En8lucH6LLlkoPdEtNg2m+JPorFeetOWlsxR/+W
S1Gg1Yn9AgMBAAECggEAEHssLEGiWmD+l8SxF3M0eHMKlbw2TlFVyWpfD8YzqT/B
WnH4jxHsPDWnGdbfQTVvVvtsAL4cf0DqLsq/DcFqSiFBV93sjdxADQK1T1cZ5OfS
aae9KTgOl2eATXfG0tL6cvJKwZywRAFSc/YpTGcw+u9KfP9t9+ckJYD2Gj6lrHuh
kDSfm8oOLmGn0PDoMSLt29E+k7R43FpfHori7+0drrrmiFnkLVwbzX0pq0IagL4k
/STqReUpGWURds4klb3kuabqhOHqNqFgFiAq72px9XPSqNvik+AJka6wGATobIp5
hc+SAwpo2ZKofdLkNQLPpeptm1QtVSi64CJ+NH6PAQKBgQDzMcDB7sDeP339nvpA
2M5kqgBR93p3mAZu+ZVi2s+0DUeClrsONBtiLdo0nZR1KYEtI0UYkG5lKUOlv3es
R/Oezc+Huz5iccGJnKQ5lG2TCtDGA96TWATm9pXddU3SPmrFU6bGzIkwESpiaoaW
qbFwjsPbgRN2E+KKfMmJcTqG+QKBgQDqZpVp5XXF0tI3Op568V6SNCRK4ivEBNWh
ApwD4ldMMdar0B0RMPnliyzImOIpfLDl4lS4uqTOQosmHb69AubB+LrQQ6yqQDpR
PpaApZf4ybn0CN6FN6zEERMUJM3/ei8wd2bN+6usQByvtJDR13C1jHNyt6Zrlqw/
Ati0QTpIJQKBgQDPGmif/vYKjqF50eAmRzwE5+1b4FhP7oxUB4IbbGIDYGesozZr
Ex7azleMBUI/QHg8e1PFZoJM7gYo6dQ9SA0FCRoZ6fBnn56E1XvZeTiTR1uhtfvf
GM8b7ZSUwufiCrucje9yTw7pe0TQCQ3S0nJEe5/5l4N+Q9LhwwFSZbXE6QKBgQDX
0CN5IJ9SyExsNTh9EYZ1LjTMDXkmPR1D5Vcn7Flb+fcgsbhRf7pVsdJFzx1L/VYS
ElTW0GG01mevbGuVMvqrVQsLfYOYLRKEgw+m2tAVbAYdvZzDIwOace4S+eAAfMq9
4PFybWkeatj+nU1JJwbK4MnasWQ0YsGsMj67l+LFUQKBgBqDxJ/b5eOYWnithbjT
joAk7VsnK13XcHFEnnGOFZAcay0lTDZ3Q3KvMBfOVkjvl2dF8KtGY/ne7yL9lsya
rIsqK+0aR/6aLKdbtEwI+ESSjSK6ACq88V/FdxAsvPeePxVwxVgIH/7MKOQFbAtq
w8CwQZ2MEuepFZQOrsWYfQ4X
-----END PRIVATE KEY-----
''';

class _FakeConnectionInfo implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  @override
  final int localPort;
  @override
  final int remotePort;
  _FakeConnectionInfo(String ip)
    : remoteAddress = InternetAddress(ip),
      localPort = 8080,
      remotePort = 54321;
}

Request _request({String? socketIp, Map<String, String> headers = const {}}) =>
    Request(
      'GET',
      Uri.parse('http://localhost/test'),
      headers: headers,
      context: {
        if (socketIp != null)
          'shelf.io.connection_info': _FakeConnectionInfo(socketIp),
      },
    );

ApiRoute<void, String> _route(String path, {List<String> tags = const []}) =>
    ApiRoute<void, String>(
      method: ApiMethod.get,
      path: path,
      typedHandler: (req, _) async => 'ok',
      summary: path,
      tags: tags,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // clientIp
  // ───────────────────────────────────────────────────────────────────────────

  group('clientIp', () {
    test('returns socket IP by default', () {
      expect(clientIp(_request(socketIp: '10.1.2.3')), '10.1.2.3');
    });

    test('ignores X-Forwarded-For unless trustProxy is set', () {
      final req = _request(
        socketIp: '10.1.2.3',
        headers: {'x-forwarded-for': '99.99.99.99'},
      );
      expect(clientIp(req), '10.1.2.3');
    });

    test('uses first X-Forwarded-For entry when trustProxy is set', () {
      final req = _request(
        socketIp: '10.1.2.3',
        headers: {'x-forwarded-for': '203.0.113.7, 10.0.0.1'},
      );
      expect(clientIp(req, trustProxy: true), '203.0.113.7');
    });

    test('falls back to X-Real-IP when trustProxy is set and no XFF', () {
      final req = _request(
        socketIp: '10.1.2.3',
        headers: {'x-real-ip': '203.0.113.9'},
      );
      expect(clientIp(req, trustProxy: true), '203.0.113.9');
    });

    test('trustProxy without proxy headers falls back to socket IP', () {
      expect(
        clientIp(_request(socketIp: '10.1.2.3'), trustProxy: true),
        '10.1.2.3',
      );
    });

    test('empty X-Forwarded-For falls through to socket IP', () {
      final req = _request(
        socketIp: '10.1.2.3',
        headers: {'x-forwarded-for': '  '},
      );
      expect(clientIp(req, trustProxy: true), '10.1.2.3');
    });

    test('returns unknown without connection info or headers', () {
      expect(clientIp(_request()), 'unknown');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Rate limiter + trustProxy
  // ───────────────────────────────────────────────────────────────────────────

  group('rateLimitMiddleware trustProxy', () {
    Handler limited({bool trustProxy = false}) => rateLimitMiddleware(
      maxRequests: 1,
      window: const Duration(minutes: 1),
      trustProxy: trustProxy,
    )((_) async => Response.ok('ok'));

    test('spoofed X-Forwarded-For cannot dodge the limiter', () async {
      final handler = limited();
      // Same socket, rotating fake XFF — must share one bucket.
      final first = await handler(
        _request(socketIp: '10.0.0.5', headers: {'x-forwarded-for': '1.1.1.1'}),
      );
      final second = await handler(
        _request(socketIp: '10.0.0.5', headers: {'x-forwarded-for': '2.2.2.2'}),
      );
      expect(first.statusCode, 200);
      expect(second.statusCode, 429);
    });

    test('distinct socket IPs get distinct buckets', () async {
      final handler = limited();
      expect((await handler(_request(socketIp: '10.0.0.1'))).statusCode, 200);
      expect((await handler(_request(socketIp: '10.0.0.2'))).statusCode, 200);
      expect((await handler(_request(socketIp: '10.0.0.1'))).statusCode, 429);
    });

    test('behind a proxy, trustProxy keys by forwarded IP', () async {
      final handler = limited(trustProxy: true);
      // Same proxy socket, different real clients — separate buckets.
      final a = await handler(
        _request(socketIp: '10.0.0.5', headers: {'x-forwarded-for': '1.1.1.1'}),
      );
      final b = await handler(
        _request(socketIp: '10.0.0.5', headers: {'x-forwarded-for': '2.2.2.2'}),
      );
      final aAgain = await handler(
        _request(socketIp: '10.0.0.5', headers: {'x-forwarded-for': '1.1.1.1'}),
      );
      expect(a.statusCode, 200);
      expect(b.statusCode, 200);
      expect(aAgain.statusCode, 429);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Route prefixing
  // ───────────────────────────────────────────────────────────────────────────

  group('route prefix', () {
    test('routes are served under the prefix', () async {
      final router = RouterManager();
      router.registerController(
        InlineController([_route('/users')]),
        prefix: '/api/v1',
      );
      final client = DartApiTestClient(router.handler.call);
      expect((await client.get('/api/v1/users')).statusCode, 200);
      expect((await client.get('/users')).statusCode, 404);
    });

    test('collectedRoutes reflects the prefixed path (OpenAPI)', () {
      final router = RouterManager();
      router.registerController(
        InlineController([_route('/users')]),
        prefix: '/api/v1',
      );
      expect(router.collectedRoutes.single.path, '/api/v1/users');
    });

    test('prefix is normalized (missing/trailing slashes)', () async {
      final router = RouterManager();
      router.registerController(
        InlineController([_route('/a')]),
        prefix: 'api/v1/',
      );
      final client = DartApiTestClient(router.handler.call);
      expect((await client.get('/api/v1/a')).statusCode, 200);
    });

    test('root route under prefix maps to the prefix itself', () async {
      final router = RouterManager();
      router.registerController(
        InlineController([_route('/')]),
        prefix: '/api',
      );
      final client = DartApiTestClient(router.handler.call);
      expect((await client.get('/api')).statusCode, 200);
    });

    test('empty prefix leaves paths untouched', () {
      final router = RouterManager();
      router.registerController(InlineController([_route('/plain')]));
      expect(router.collectedRoutes.single.path, '/plain');
    });

    test('controller tag still applied with prefix', () {
      final router = RouterManager();
      router.registerController(
        InlineController([_route('/x')], tag: 'Things'),
        prefix: '/api',
      );
      expect(router.collectedRoutes.single.tags, ['Things']);
      expect(router.collectedRoutes.single.path, '/api/x');
    });

    test('DartAPI.addControllers forwards the prefix', () async {
      final app = DartAPI();
      app.addControllers([
        InlineController([_route('/ping')]),
      ], prefix: '/api/v2');
      app.enableHealthCheck();
      await app.start(port: 0, address: 'localhost');
      addTearDown(() => app.stop(force: true));

      final res = await HttpClient()
          .getUrl(Uri.parse('http://localhost:${app.port}/api/v2/ping'))
          .then((r) => r.close());
      expect(res.statusCode, 200);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Static files
  // ───────────────────────────────────────────────────────────────────────────

  group('serveStatic', () {
    test('serves files from a directory under the prefix', () async {
      final dir = Directory.systemTemp.createTempSync('dartapi_static');
      File('${dir.path}/hello.txt').writeAsStringSync('static works');
      addTearDown(() => dir.deleteSync(recursive: true));

      final app = DartAPI();
      app.serveStatic('/public', dir.path);
      await app.start(port: 0, address: 'localhost');
      addTearDown(() => app.stop(force: true));

      final res = await HttpClient()
          .getUrl(Uri.parse('http://localhost:${app.port}/public/hello.txt'))
          .then((r) => r.close());
      expect(res.statusCode, 200);
      expect(await utf8.decodeStream(res), 'static works');
    });

    test('missing file returns 404', () async {
      final dir = Directory.systemTemp.createTempSync('dartapi_static');
      addTearDown(() => dir.deleteSync(recursive: true));

      final app = DartAPI();
      app.serveStatic('/public', dir.path);
      await app.start(port: 0, address: 'localhost');
      addTearDown(() => app.stop(force: true));

      final res = await HttpClient()
          .getUrl(Uri.parse('http://localhost:${app.port}/public/nope.txt'))
          .then((r) => r.close());
      expect(res.statusCode, 404);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Graceful shutdown
  // ───────────────────────────────────────────────────────────────────────────

  group('graceful shutdown', () {
    test('stop() drains in-flight requests instead of aborting them', () async {
      final handlerStarted = Completer<void>();
      final app = DartAPI(shutdownGracePeriod: const Duration(seconds: 10));
      app.addControllers([
        InlineController([
          ApiRoute<void, String>(
            method: ApiMethod.get,
            path: '/slow',
            typedHandler: (req, _) async {
              handlerStarted.complete();
              await Future<void>.delayed(const Duration(milliseconds: 300));
              return 'finished';
            },
            summary: 'slow',
          ),
        ]),
      ]);
      await app.start(port: 0, address: 'localhost');
      final port = app.port;

      final client = HttpClient();
      final inFlight = client
          .getUrl(Uri.parse('http://localhost:$port/slow'))
          .then((r) => r.close());

      // Initiate shutdown while the request is inside the handler.
      await handlerStarted.future;
      final stopped = app.stop();

      final res = await inFlight;
      expect(res.statusCode, 200);
      expect(await utf8.decodeStream(res), contains('finished'));
      await stopped;
      client.close();
    });

    test('shutdown hooks run after in-flight requests drain', () async {
      final handlerStarted = Completer<void>();
      final order = <String>[];
      final app = DartAPI(shutdownGracePeriod: const Duration(seconds: 5));
      app.onShutdown(() async => order.add('hook'));
      app.addControllers([
        InlineController([
          ApiRoute<void, String>(
            method: ApiMethod.get,
            path: '/slow',
            typedHandler: (req, _) async {
              handlerStarted.complete();
              await Future<void>.delayed(const Duration(milliseconds: 200));
              order.add('handler-finished');
              return 'ok';
            },
            summary: 'slow',
          ),
        ]),
      ]);
      await app.start(port: 0, address: 'localhost');
      final port = app.port;

      final client = HttpClient();
      final inFlight = client
          .getUrl(Uri.parse('http://localhost:$port/slow'))
          .then((r) => r.close());
      await handlerStarted.future;

      await app.stop();
      await inFlight;
      client.close();

      expect(order, ['handler-finished', 'hook']);
    });

    test('stop() is idempotent', () async {
      final app = DartAPI();
      app.addControllers([InlineController([])]);
      await app.start(port: 0, address: 'localhost');
      await app.stop();
      await app.stop(); // second call must be a no-op
      expect(app.port, isNull);
    });

    test('force-closes when the grace period is exceeded', () async {
      final app = DartAPI(
        shutdownGracePeriod: const Duration(milliseconds: 100),
      );
      final blocker = Completer<String>();
      app.addControllers([
        InlineController([
          ApiRoute<void, String>(
            method: ApiMethod.get,
            path: '/stuck',
            typedHandler: (req, _) => blocker.future,
            summary: 'stuck',
          ),
        ]),
      ]);
      await app.start(port: 0, address: 'localhost');
      final port = app.port;

      final client = HttpClient();
      // Request that never completes on its own.
      unawaited(
        client
            .getUrl(Uri.parse('http://localhost:$port/stuck'))
            .then((r) => r.close())
            .then((_) {}, onError: (_) {}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // stop() must return promptly (grace 100ms), not hang forever.
      await app.stop().timeout(const Duration(seconds: 5));
      client.close(force: true);
      blocker.complete('too late');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // TLS
  // ───────────────────────────────────────────────────────────────────────────

  group('TLS', () {
    test('start(securityContext:) serves HTTPS', () async {
      final context =
          SecurityContext()
            ..useCertificateChainBytes(utf8.encode(_testCertPem))
            ..usePrivateKeyBytes(utf8.encode(_testKeyPem));

      final app = DartAPI();
      app.addControllers([
        InlineController([_route('/secure')]),
      ]);
      await app.start(port: 0, address: 'localhost', securityContext: context);
      addTearDown(() => app.stop(force: true));

      final client =
          HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final res = await client
          .getUrl(Uri.parse('https://localhost:${app.port}/secure'))
          .then((r) => r.close());
      expect(res.statusCode, 200);
      client.close();
    });
  });
}
