import 'dart:convert';
import 'dart:io';

import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _req({bool gzipAccepted = true}) => Request(
      'GET',
      Uri.parse('http://localhost/test'),
      headers: gzipAccepted ? {'Accept-Encoding': 'gzip, deflate'} : {},
    );

Handler _makeHandler(String body, {int threshold = 0}) =>
    compressionMiddleware(threshold: threshold)(
      (req) => Response.ok(body),
    );

void main() {
  group('compressionMiddleware', () {
    test('compresses response when client accepts gzip', () async {
      final handler = _makeHandler('a' * 200, threshold: 100);
      final res = await handler(_req());
      expect(res.headers['content-encoding'], equals('gzip'));
    });

    test('does not compress when client does not accept gzip', () async {
      final handler = _makeHandler('a' * 200, threshold: 0);
      final res = await handler(_req(gzipAccepted: false));
      expect(res.headers['content-encoding'], isNull);
    });

    test('does not compress when body is below threshold', () async {
      final handler = _makeHandler('small', threshold: 10000);
      final res = await handler(_req());
      expect(res.headers['content-encoding'], isNull);
    });

    test('compressed body can be decompressed back to original', () async {
      final original = 'Hello, DartAPI! ' * 50;
      final handler = _makeHandler(original, threshold: 0);
      final res = await handler(_req());
      expect(res.headers['content-encoding'], equals('gzip'));
      final bytes = await res.read().toList();
      final flat = bytes.expand((b) => b).toList();
      final decompressed = utf8.decode(gzip.decode(flat));
      expect(decompressed, equals(original));
    });

    test('sets content-length to compressed size', () async {
      final handler = _makeHandler('x' * 500, threshold: 0);
      final res = await handler(_req());
      final bytes = await res.read().toList();
      final flat = bytes.expand((b) => b).toList();
      expect(res.headers['content-length'], equals(flat.length.toString()));
    });

    test('does not re-compress already encoded responses', () async {
      final preCompressed =
          gzip.encode(utf8.encode('already compressed content'));
      final h = compressionMiddleware(threshold: 0)((req) => Response.ok(
            preCompressed,
            headers: {'content-encoding': 'gzip'},
          ));
      final res = await h(_req());
      // content-encoding was already set — middleware should not touch it
      expect(res.headers['content-encoding'], equals('gzip'));
      // body should be the original compressed bytes (not double-compressed)
      final body = await res.read().toList();
      final flat = body.expand((b) => b).toList();
      expect(utf8.decode(gzip.decode(flat)), equals('already compressed content'));
    });

    test('preserves other response headers', () async {
      final h = compressionMiddleware(threshold: 0)((req) => Response.ok(
            'x' * 200,
            headers: {'X-Custom': 'my-value'},
          ));
      final res = await h(_req());
      expect(res.headers['x-custom'], equals('my-value'));
    });
  });
}
