import 'package:dartapi_core/dartapi_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ApiRoute deprecated', () {
    test('defaults to false', () {
      final route = ApiRoute<void, void>(
        method: ApiMethod.get,
        path: '/ping',
        typedHandler: (_, _) async {},
      );
      expect(route.deprecated, isFalse);
    });

    test('deprecated route adds Deprecation: true response header', () async {
      final route = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/v1/users',
        deprecated: true,
        typedHandler: (_, _) async => {'data': []},
      );
      final req = Request('GET', Uri.parse('http://localhost/v1/users'));
      final res = await route.handler(req);
      expect(res.headers['deprecation'], equals('true'));
    });

    test('non-deprecated route has no Deprecation header', () async {
      final route = ApiRoute<void, Map<String, dynamic>>(
        method: ApiMethod.get,
        path: '/v2/users',
        typedHandler: (_, _) async => {'data': []},
      );
      final req = Request('GET', Uri.parse('http://localhost/v2/users'));
      final res = await route.handler(req);
      expect(res.headers['deprecation'], isNull);
    });

    test('withTags preserves deprecated flag', () {
      final route = ApiRoute<void, void>(
        method: ApiMethod.get,
        path: '/old',
        deprecated: true,
        typedHandler: (_, _) async {},
      );
      final copied = route.withTags(['Legacy']);
      expect(copied.deprecated, isTrue);
    });
  });

  group('OpenApiGenerator deprecated', () {
    test('emits deprecated:true in spec for deprecated routes', () {
      final route = ApiRoute<void, void>(
        method: ApiMethod.get,
        path: '/v1/users',
        deprecated: true,
        typedHandler: (_, _) async {},
      );
      final spec = OpenApiGenerator(routes: [route], title: 'Test').generate();
      final op =
          (spec['paths'] as Map)['/v1/users']['get'] as Map<String, dynamic>;
      expect(op['deprecated'], isTrue);
    });

    test('does not emit deprecated for normal routes', () {
      final route = ApiRoute<void, void>(
        method: ApiMethod.get,
        path: '/v2/users',
        typedHandler: (_, _) async {},
      );
      final spec = OpenApiGenerator(routes: [route], title: 'Test').generate();
      final op =
          (spec['paths'] as Map)['/v2/users']['get'] as Map<String, dynamic>;
      expect(op.containsKey('deprecated'), isFalse);
    });
  });
}
