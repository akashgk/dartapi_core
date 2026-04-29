import 'package:dartapi_core/dartapi_core.dart';
import 'package:test/test.dart';

class _TestConfig extends EnvConfig {
  _TestConfig({super.environment});

  String get host => env('HOST', defaultValue: 'localhost');
  int get port => envInt('PORT', defaultValue: 8080);
  double get ratio => envDouble('RATIO', defaultValue: 1.5);
  bool get debug => envBool('DEBUG', defaultValue: false);
  String get secret => env('SECRET');
}

_TestConfig _cfg(Map<String, String> env) => _TestConfig(environment: env);

void main() {
  group('EnvConfig defaults', () {
    final config = _TestConfig(environment: {});

    test(
      'returns string default',
      () => expect(config.host, equals('localhost')),
    );
    test('returns int default', () => expect(config.port, equals(8080)));
    test('returns double default', () => expect(config.ratio, equals(1.5)));
    test('returns bool default', () => expect(config.debug, isFalse));
  });

  group('EnvConfig reads values', () {
    test(
      'reads string',
      () => expect(_cfg({'HOST': 'db.internal'}).host, equals('db.internal')),
    );
    test('reads int', () => expect(_cfg({'PORT': '9090'}).port, equals(9090)));
    test(
      'reads double',
      () => expect(_cfg({'RATIO': '3.14'}).ratio, equals(3.14)),
    );
    test(
      'reads bool true',
      () => expect(_cfg({'DEBUG': 'true'}).debug, isTrue),
    );
    test(
      'reads bool TRUE (case-insensitive)',
      () => expect(_cfg({'DEBUG': 'TRUE'}).debug, isTrue),
    );
    test(
      'reads bool non-true as false',
      () => expect(_cfg({'DEBUG': 'yes'}).debug, isFalse),
    );
  });

  group('EnvConfig errors', () {
    test('throws MissingEnvException for required absent var', () {
      expect(
        () => _TestConfig(environment: {}).secret,
        throwsA(isA<MissingEnvException>()),
      );
    });

    test('MissingEnvException message includes key name', () {
      try {
        _TestConfig(environment: {}).secret;
      } on MissingEnvException catch (e) {
        expect(e.toString(), contains('SECRET'));
      }
    });

    test('throws InvalidEnvException for unparseable int', () {
      expect(
        () => _cfg({'PORT': 'bad'}).port,
        throwsA(isA<InvalidEnvException>()),
      );
    });

    test('throws InvalidEnvException for unparseable double', () {
      expect(
        () => _cfg({'RATIO': 'bad'}).ratio,
        throwsA(isA<InvalidEnvException>()),
      );
    });

    test('InvalidEnvException message includes key and value', () {
      try {
        _cfg({'PORT': 'bad'}).port;
      } on InvalidEnvException catch (e) {
        expect(e.toString(), contains('PORT'));
        expect(e.toString(), contains('bad'));
      }
    });
  });
}
