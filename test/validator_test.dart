import 'package:test/test.dart';
import 'package:dartapi_core/dartapi_core.dart';

void main() {
  group('Validators', () {
    test('EmailValidator accepts valid email', () {
      final validator = EmailValidator('Invalid email');
      expect(validator.validate('test@example.com'), isTrue);
    });

    test('EmailValidator rejects invalid email', () {
      final validator = EmailValidator('Invalid email');
      expect(validator.validate('invalid-email'), isFalse);
    });
  });
}
