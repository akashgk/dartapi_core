import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('MapExtensions', () {
    test('verifyKey returns valid typed value', () {
      final map = {'name': 'John'};
      final value = map.verifyKey<String>('name');
      expect(value, equals('John'));
    });

    test('verifyKey throws on missing key', () {
      final map = {'name': 'John'};
      expect(() => map.verifyKey<String>('age'), throwsException);
    });

    test('verifyKey throws on wrong type', () {
      final map = {'age': 30};
      expect(() => map.verifyKey<String>('age'), throwsException);
    });
  });
}
