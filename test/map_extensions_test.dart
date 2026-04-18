import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('MapExtensions - verifyKey', () {
    test('returns value when key exists and type matches', () {
      final map = {'name': 'John'};
      expect(map.verifyKey<String>('name'), equals('John'));
    });

    test('returns int value', () {
      final map = {'age': 30};
      expect(map.verifyKey<int>('age'), equals(30));
    });

    test('returns bool value', () {
      final map = {'active': true};
      expect(map.verifyKey<bool>('active'), isTrue);
    });

    test('throws ApiException 422 when key is missing', () {
      final map = {'name': 'John'};
      expect(
        () => map.verifyKey<String>('email'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.message, 'message', contains('"email"')),
        ),
      );
    });

    test('throws ApiException 422 when type does not match', () {
      final map = {'age': '30'}; // String, not int
      expect(
        () => map.verifyKey<int>('age'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.message, 'message', contains('"age"')),
        ),
      );
    });

    test('throws ApiException 422 when validator fails', () {
      final map = {'email': 'not-an-email'};
      expect(
        () => map.verifyKey<String>('email', validators: [
          EmailValidator('Invalid email format'),
        ]),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.message, 'message', equals('Invalid email format')),
        ),
      );
    });

    test('passes when validator succeeds', () {
      final map = {'email': 'user@example.com'};
      expect(
        map.verifyKey<String>('email', validators: [
          EmailValidator('Invalid email'),
        ]),
        equals('user@example.com'),
      );
    });

    test('runs multiple validators and fails on first failure', () {
      final map = {'email': 'bad'};
      expect(
        () => map.verifyKey<String>('email', validators: [
          EmailValidator('Invalid email'),
        ]),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    });
  });
}
